<#
.SYNOPSIS
    Validates an infra-spec.yaml against the spec contract.

.DESCRIPTION
    Read-only. Checks what the contract in references/spec.md promises:

      1. The file parses as YAML, and carries schema_version, spec.id and
         spec.target.
      2. Every decision value carries a known `source`. A value without one is a
         settings dump entry, not a recorded decision.
      3. `overridden` carries a reason, and `forced` carries `forced_by`. An
         undocumented exception reads as an accident a year later.
      4. `assumed` values and `open:` entries are reported, with what they block.
         A spec holding either is valid - it is not applyable, which is the
         distinction the exit code makes.
      5. No decision key uses a backend's attribute spelling
         (public_network_access_enabled, allowBlobPublicAccess, ...). The spec
         names decisions; one backend's vocabulary in it breaks the others.
      6. composition: unique module ids, every resource contained exactly once,
         `needs` pointing at declared modules and acyclic, `implementation`
         being avm|authored|reuse rather than a module path.

    Parsing needs a YAML reader. powershell-yaml if present, otherwise python
    with PyYAML. Without either the script says so and exits 2 rather than
    pretending the file is fine.

.PARAMETER Path
    The infra-spec.yaml to check.

.PARAMETER RequireApplyable
    Also fail on `assumed` values and on open entries that block apply. Use
    before applying; leave off while iterating on a spec.

.EXAMPLE
    pwsh -NoProfile -File Test-Spec.ps1 ./infra-spec.yaml
    pwsh -NoProfile -File Test-Spec.ps1 ./infra-spec.yaml -RequireApplyable

.OUTPUTS
    Exit 0 clean, 1 contract violations, 2 could not check (no parser, no file).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string] $Path,

    [switch] $RequireApplyable
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$knownSources = @('stated', 'asked', 'pattern', 'deployment', 'forced', 'assumed', 'default', 'carried', 'overridden')
$knownBlocks  = @('render', 'plan', 'apply')

# Attribute spellings that belong to a backend, not to a decision. Matched
# against decision keys only - a `renders:` field naming them is correct.
$backendSpellings = @(
    'public_network_access_enabled', 'allow_nested_items_to_be_public',
    'shared_access_key_enabled_bool', 'https_traffic_only_enabled',
    'allowBlobPublicAccess', 'publicNetworkAccess', 'allowSharedKeyAccess',
    'supportsHttpsTrafficOnly', 'minimumTlsVersion', 'requireInfrastructureEncryption'
)

$errors   = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
$notes    = [System.Collections.Generic.List[string]]::new()

function Write-Head($text) { Write-Host $text -ForegroundColor Cyan }
function Write-Ok($text)   { Write-Host "[ ok ] $text" -ForegroundColor Green }
function Write-Bad($text)  { Write-Host "[fail] $text" -ForegroundColor Red }
function Write-Warn($text) { Write-Host "[warn] $text" -ForegroundColor Yellow }

# --- read it ---------------------------------------------------------------

if (-not (Test-Path -LiteralPath $Path)) {
    Write-Bad "no such file: $Path"
    exit 2
}

$full = (Resolve-Path -LiteralPath $Path).Path
$raw  = Get-Content -LiteralPath $full -Raw

function ConvertFrom-SpecYaml {
    param([string] $Text, [string] $File)

    if (Get-Module -ListAvailable -Name powershell-yaml) {
        Import-Module powershell-yaml -ErrorAction Stop
        return ($Text | ConvertFrom-Yaml)
    }

    foreach ($py in @('python', 'python3', 'py')) {
        $exe = (Get-Command $py -ErrorAction SilentlyContinue)
        if (-not $exe) { continue }
        $probe = & $exe -c 'import yaml' 2>&1
        if ($LASTEXITCODE -ne 0) { continue }

        # default=str: YAML resolves timestamps to datetime, which json cannot serialise.
        $json = & $exe -c 'import sys,yaml,json;json.dump(yaml.safe_load(open(sys.argv[1],encoding="utf-8")),sys.stdout,default=str)' $File 2>&1
        if ($LASTEXITCODE -ne 0) { throw "YAML does not parse: $json" }
        return ($json | ConvertFrom-Json -AsHashtable)
    }

    throw 'NO_PARSER'
}

$spec = $null
try {
    $spec = ConvertFrom-SpecYaml -Text $raw -File $full
} catch {
    if ($_.Exception.Message -eq 'NO_PARSER') {
        Write-Bad 'no YAML parser available'
        Write-Host '       Install one and re-run:' -ForegroundColor DarkGray
        Write-Host '         Install-Module powershell-yaml -Scope CurrentUser' -ForegroundColor DarkGray
        Write-Host '         or: pip install pyyaml' -ForegroundColor DarkGray
        exit 2
    }
    Write-Bad $_.Exception.Message
    exit 1
}

if ($null -eq $spec) {
    Write-Bad 'the file parsed as empty'
    exit 1
}

Write-Head "Spec check - $full"
Write-Host ('-' * 70)

function Test-Key($map, [string] $key) {
    if ($null -eq $map) { return $false }
    if ($map -is [System.Collections.IDictionary]) { return $map.Contains($key) }
    return $null -ne ($map.PSObject.Properties[$key])
}
function Get-Val($map, [string] $key) {
    if (-not (Test-Key $map $key)) { return $null }
    if ($map -is [System.Collections.IDictionary]) { return $map[$key] }
    return $map.$key
}
function Get-Keys($map) {
    if ($null -eq $map) { return @() }
    if ($map -is [System.Collections.IDictionary]) { return @($map.Keys) }
    return @($map.PSObject.Properties.Name)
}

# --- 1. envelope -----------------------------------------------------------

foreach ($k in @('schema_version', 'spec')) {
    if (-not (Test-Key $spec $k)) { $errors.Add("top level: '$k' is missing") }
}
$specHead = Get-Val $spec 'spec'
foreach ($k in @('id', 'target')) {
    if (-not (Test-Key $specHead $k)) { $errors.Add("spec.$k is missing") }
}
$target = Get-Val $specHead 'target'
if ($target -and $target -notin @('terraform', 'bicep', 'api')) {
    $errors.Add("spec.target '$target' is not terraform, bicep or api")
}
if ($errors.Count -eq 0) { Write-Ok "envelope - id '$(Get-Val $specHead 'id')', target '$target'" }

# --- 2-5. walk every decision ----------------------------------------------

$decisions = 0
$assumed   = [System.Collections.Generic.List[string]]::new()

function Test-Decision {
    param($node, [string] $path)

    # A decision is a map carrying a `value`. Anything else is a container.
    if ($node -is [System.Collections.IDictionary] -or
        ($node -isnot [string] -and $node -isnot [int] -and $node -isnot [bool] -and
         $node -isnot [array] -and $null -ne $node -and $node.PSObject.Properties.Count -gt 0)) {

        if (Test-Key $node 'value') {
            $script:decisions++
            $src = Get-Val $node 'source'

            if (-not $src) {
                $script:errors.Add("$path has a value but no source. Strip provenance and the spec is a settings dump.")
            } elseif ($src -notin $knownSources) {
                $script:errors.Add("$path has source '$src', which is not one of: $($knownSources -join ', ')")
            } else {
                switch ($src) {
                    'overridden' {
                        if (-not ((Test-Key $node 'reason') -or (Test-Key $node 'note') -or (Test-Key $node 'departs_from'))) {
                            $script:errors.Add("$path is overridden with no reason. An undocumented exception reads as an accident later.")
                        }
                    }
                    'forced' {
                        if (-not (Test-Key $node 'forced_by')) {
                            $script:errors.Add("$path is forced with no forced_by. The chain is the point - what forced it?")
                        }
                    }
                    'assumed' {
                        $script:assumed.Add($path)
                    }
                }
            }
            return
        }

        foreach ($k in (Get-Keys $node)) {
            if ("$k".StartsWith('_')) { continue }   # _target_overrides is quarantined on purpose
            foreach ($bad in $backendSpellings) {
                if ("$k" -eq $bad) {
                    $script:errors.Add("$path.$k uses a backend's attribute spelling. The spec names decisions; renderers know attributes.")
                }
            }
            Test-Decision -node (Get-Val $node $k) -path "$path.$k"
        }
    }
}

foreach ($section in @('deployment', 'resources', 'wiring')) {
    if (Test-Key $spec $section) {
        Test-Decision -node (Get-Val $spec $section) -path $section
    }
}

if ($decisions -eq 0) {
    $warnings.Add('no decisions found - deployment:, resources: and wiring: are all empty or absent')
} else {
    Write-Ok "$decisions decision(s), each with a known source"
}

# --- 6. composition --------------------------------------------------------

if (Test-Key $spec 'composition') {
    $comp = Get-Val $spec 'composition'
    $gran = Get-Val $comp 'granularity'
    if ($gran -and $gran -notin @('single', 'per-concern', 'per-resource')) {
        $errors.Add("composition.granularity '$gran' is not single, per-concern or per-resource")
    }

    $modules = @(@(Get-Val $comp 'modules') | Where-Object { $_ })
    $ids = @($modules | ForEach-Object { Get-Val $_ 'id' })
    $dupes = @($ids | Group-Object | Where-Object Count -gt 1 | ForEach-Object Name)
    if ($dupes.Count -gt 0) { $errors.Add("composition: duplicate module id(s): $($dupes -join ', ')") }

    foreach ($m in $modules) {
        $mid  = Get-Val $m 'id'
        $impl = Get-Val $m 'implementation'
        if ($impl -and $impl -notin @('avm', 'authored', 'reuse')) {
            $errors.Add("composition.$mid.implementation '$impl' is not avm, authored or reuse. A module path belongs in the renderer.")
        }
        foreach ($n in @(Get-Val $m 'needs')) {
            if ($n -and $n -notin $ids) { $errors.Add("composition.$mid needs '$n', which is not a declared module") }
        }
    }

    # needs must be acyclic
    $edges = @{}
    foreach ($m in $modules) { $edges[(Get-Val $m 'id')] = @(Get-Val $m 'needs') }
    $state = @{}
    function Test-Cycle([string] $node, [string[]] $stack) {
        if ($script:state[$node] -eq 'done') { return }
        if ($script:state[$node] -eq 'open') {
            $script:errors.Add("composition: needs cycle - $((@($stack) + $node) -join ' -> '). Two modules that need each other are one module.")
            return
        }
        $script:state[$node] = 'open'
        foreach ($n in $edges[$node]) { if ($n) { Test-Cycle -node $n -stack (@($stack) + $node) } }
        $script:state[$node] = 'done'
    }
    foreach ($id in $ids) { if ($id) { Test-Cycle -node $id -stack @() } }

    # every resource in exactly one module - moot for `single`, which is "one root, no modules" by contract
    if ($gran -ne 'single' -and (Test-Key $spec 'resources')) {
        $contained = @($modules | ForEach-Object { @(Get-Val $_ 'contains') } | Where-Object { $_ })
        foreach ($r in (Get-Keys (Get-Val $spec 'resources'))) {
            $hits = @($contained | Where-Object { $_ -eq $r }).Count
            if ($hits -eq 0) { $errors.Add("composition: resource '$r' is in no module") }
            if ($hits -gt 1) { $errors.Add("composition: resource '$r' is in $hits modules; it belongs to exactly one") }
        }
    }

    if ($modules.Count -gt 0) { Write-Ok "composition - $($modules.Count) module(s), needs acyclic" }
}

# --- open: and assumed -----------------------------------------------------

$blockingApply = [System.Collections.Generic.List[string]]::new()

if (Test-Key $spec 'open') {
    foreach ($o in @(Get-Val $spec 'open')) {
        $k = Get-Val $o 'key'
        $b = Get-Val $o 'blocks'
        if (-not $k) { $errors.Add('open: an entry has no key') }
        if (-not $b) {
            $errors.Add("open.$k has no blocks: say what it stops - render, plan or apply")
        } elseif ($b -notin $knownBlocks) {
            $errors.Add("open.$k blocks '$b', which is not render, plan or apply")
        } else {
            $notes.Add("open: $k (blocks $b)")
            if ($b -in @('render', 'plan', 'apply')) { $blockingApply.Add("$k ($b)") }
        }
    }
}
foreach ($a in $assumed) { $blockingApply.Add("$a (assumed)") }

Write-Host ('-' * 70)

foreach ($n in $notes) { Write-Host "  $n" -ForegroundColor DarkGray }
if ($assumed.Count -gt 0) {
    Write-Warn "$($assumed.Count) assumed value(s) - renders and plans, never applies"
    foreach ($a in $assumed) { Write-Host "         $a" -ForegroundColor DarkGray }
}

if ($warnings.Count -gt 0) { foreach ($w in $warnings) { Write-Warn $w } }

if ($errors.Count -gt 0) {
    Write-Host ''
    Write-Bad "$($errors.Count) contract violation(s)"
    foreach ($e in $errors) { Write-Host "         $e" -ForegroundColor DarkGray }
    exit 1
}

if ($RequireApplyable -and $blockingApply.Count -gt 0) {
    Write-Host ''
    Write-Bad "not applyable - $($blockingApply.Count) unresolved item(s)"
    foreach ($b in $blockingApply) { Write-Host "         $b" -ForegroundColor DarkGray }
    Write-Host '       Resolve them, or drop -RequireApplyable to check the contract only.' -ForegroundColor DarkGray
    exit 1
}

Write-Host ''
if ($blockingApply.Count -gt 0) {
    Write-Host "Contract ok. $($blockingApply.Count) item(s) still block apply - re-run with -RequireApplyable to fail on them." -ForegroundColor Yellow
} else {
    Write-Host 'Contract ok, nothing unresolved.' -ForegroundColor Green
}
exit 0

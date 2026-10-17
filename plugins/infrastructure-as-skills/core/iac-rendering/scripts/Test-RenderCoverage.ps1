<#
.SYNOPSIS
    Checks that every decision in an infra-spec.yaml is asserted by the
    rendered Terraform tests.

.DESCRIPTION
    Read-only. The rendering contract (core/iac-rendering/SKILL.md) says a
    render is not finished until every decision under `resources:` is asserted
    by exactly one test, or named as not observable in a plan with its reason.
    This script makes that a check instead of a claim.

    It reads the spec's `resources:` block - every key path
    `<resource>.<group>.<question>` that carries a `value` is a decision - and
    scans the `.tftest.hcl` files beside the spec for the markers the idiom
    prescribes:

        # decision: storage-account.security.min_tls_version
        # not-testable: storage-account.networking.allow_azure_services_bypass - <why>

    Then:
      1. A decision with neither marker is unasserted. Error.
      2. A decision with both, or marked twice, is ambiguous. Error.
      3. A not-testable marker without a reason after the dash is a silence
         dressed up as a sentence. Error.
      4. A marker naming a decision the spec does not have is stale - the spec
         moved and the test did not. Error.
      5. A `# decision:` marker not followed by an `assert` block is a label
         on nothing. Error.

    Parsing the spec needs a YAML reader: powershell-yaml if present, otherwise
    python with PyYAML. Without either it says so and exits 2.

.PARAMETER Spec
    The infra-spec.yaml. Tests are looked up in `tests/` beside it unless
    -Tests says otherwise.

.PARAMETER Tests
    Directory holding the `.tftest.hcl` files. Defaults to <spec dir>/tests.

.EXAMPLE
    pwsh -NoProfile -File Test-RenderCoverage.ps1 ./infra/infra-spec.yaml

.OUTPUTS
    Exit 0 every decision covered, 1 gaps or stale markers, 2 could not check.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string] $Spec,

    [string] $Tests
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Variable names are case-insensitive: the parsed document is $doc, never $spec,
# or it lands in the [string] -Spec parameter and comes back as a string.

function Write-Ok($text)   { Write-Host "[ ok ] $text" -ForegroundColor Green }
function Write-Bad($text)  { Write-Host "[fail] $text" -ForegroundColor Red }

if (-not (Test-Path -LiteralPath $Spec -PathType Leaf)) {
    Write-Bad "no such file: $Spec"
    exit 2
}
$specPath = (Resolve-Path -LiteralPath $Spec).Path
if (-not $Tests) { $Tests = Join-Path (Split-Path -Parent $specPath) 'tests' }
if (-not (Test-Path -LiteralPath $Tests -PathType Container)) {
    Write-Bad "no tests directory at $Tests - a render without tests is not finished"
    exit 1
}
$testFiles = @(Get-ChildItem -LiteralPath $Tests -Filter '*.tftest.hcl' -File)
if ($testFiles.Count -eq 0) {
    Write-Bad "no .tftest.hcl in $Tests - a render without tests is not finished"
    exit 1
}

# --- read the spec ---------------------------------------------------------

function ConvertFrom-SpecYaml([string] $File) {
    if (Get-Module -ListAvailable -Name powershell-yaml) {
        Import-Module powershell-yaml -ErrorAction Stop
        return ((Get-Content -LiteralPath $File -Raw) | ConvertFrom-Yaml)
    }
    foreach ($py in @('python', 'python3', 'py')) {
        if (-not (Get-Command $py -ErrorAction SilentlyContinue)) { continue }
        & $py -c 'import yaml' 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { continue }
        $json = & $py -I -c 'import sys,yaml,json;json.dump(yaml.safe_load(open(sys.argv[1],encoding="utf-8")),sys.stdout,default=str)' $File 2>&1
        if ($LASTEXITCODE -ne 0) { throw "YAML does not parse: $json" }
        # Assigned first, then returned: `return (<pipeline>)` hands the caller
        # the JSON string here, not the hashtable.
        $parsed = $json | ConvertFrom-Json -AsHashtable
        return $parsed
    }
    throw 'NO_PARSER'
}

try {
    $doc = ConvertFrom-SpecYaml $specPath
} catch {
    if ($_.Exception.Message -eq 'NO_PARSER') {
        Write-Bad 'no YAML parser available (Install-Module powershell-yaml, or pip install pyyaml)'
        exit 2
    }
    Write-Bad $_.Exception.Message
    exit 1
}

# Every map carrying a `value` under resources: is a decision; its key path is its id.
$decisions = [System.Collections.Generic.List[string]]::new()
function Find-Decision($node, [string] $path) {
    if ($node -isnot [System.Collections.IDictionary]) { return }
    if ($node.Contains('value')) { $script:decisions.Add($path); return }
    foreach ($k in $node.Keys) {
        if ("$k".StartsWith('_')) { continue }
        Find-Decision -node $node[$k] -path ($path ? "$path.$k" : "$k")
    }
}
if ($doc -is [System.Collections.IDictionary] -and $doc.Contains('resources')) {
    Find-Decision -node $doc['resources'] -path ''
}

Write-Host "Render coverage - $specPath" -ForegroundColor Cyan
Write-Host ('-' * 70)

if ($decisions.Count -eq 0) {
    Write-Bad 'the spec has no decisions under resources: - nothing to cover'
    exit 1
}

# --- read the markers ------------------------------------------------------

$errors    = [System.Collections.Generic.List[string]]::new()
$asserted  = @{}   # decision -> file:line
$marked    = @{}   # decision -> file:line

foreach ($f in $testFiles) {
    $lines = @(Get-Content -LiteralPath $f.FullName)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $where = "$($f.Name):$($i + 1)"

        $m = [regex]::Match($line, '^\s*#\s*decision:\s*([A-Za-z0-9_.\-]+)\s*$')
        if ($m.Success) {
            $id = $m.Groups[1].Value
            if ($asserted.ContainsKey($id)) { $errors.Add("$id is asserted twice ($($asserted[$id]) and $where); one assert per decision") }
            $asserted[$id] = $where

            # The next non-blank, non-comment line has to open an assert block.
            $j = $i + 1
            while ($j -lt $lines.Count -and $lines[$j] -match '^\s*(#.*)?$') { $j++ }
            if ($j -ge $lines.Count -or $lines[$j] -notmatch '^\s*assert\s*\{') {
                $errors.Add("$id at $where is not followed by an assert block")
            }
            continue
        }

        $m = [regex]::Match($line, '^\s*#\s*not-testable:\s*([A-Za-z0-9_.\-]+)\s*(-\s*(.*))?$')
        if ($m.Success) {
            $id = $m.Groups[1].Value
            $reason = $m.Groups[3].Value.Trim()
            # The reason may continue on the next comment lines.
            $j = $i + 1
            while ($j -lt $lines.Count -and $lines[$j] -match '^\s*#\s*(\S.*)$' -and $lines[$j] -notmatch '^\s*#\s*(decision|not-testable):') {
                $reason += ' ' + $Matches[1].Trim()
                $j++
            }
            if (-not $reason) { $errors.Add("$id at $where is marked not-testable without a reason after the dash") }
            if ($marked.ContainsKey($id)) { $errors.Add("$id is marked not-testable twice ($($marked[$id]) and $where)") }
            $marked[$id] = $where
        }
    }
}

# --- compare ---------------------------------------------------------------

$covered = 0
foreach ($d in $decisions) {
    $a = $asserted.ContainsKey($d)
    $n = $marked.ContainsKey($d)
    if ($a -and $n) { $errors.Add("$d is both asserted ($($asserted[$d])) and marked not-testable ($($marked[$d])) - pick one") }
    elseif (-not $a -and -not $n) { $errors.Add("$d is neither asserted nor marked not-testable") }
    else { $covered++ }
}
foreach ($id in @($asserted.Keys) + @($marked.Keys)) {
    if ($id -notin $decisions) { $errors.Add("$id (marker at $(if ($asserted.ContainsKey($id)) { $asserted[$id] } else { $marked[$id] })) is not a decision in the spec - stale marker") }
}

Write-Ok "$($decisions.Count) decision(s) in resources:, $($asserted.Count) asserted, $($marked.Count) marked not-testable, $($testFiles.Count) test file(s)"
foreach ($id in ($marked.Keys | Sort-Object)) { Write-Host "  not-testable: $id ($($marked[$id]))" -ForegroundColor DarkGray }

Write-Host ('-' * 70)
if ($errors.Count -gt 0) {
    Write-Bad "$($errors.Count) gap(s)"
    foreach ($e in $errors) { Write-Host "         $e" -ForegroundColor DarkGray }
    exit 1
}
Write-Host "Every decision covered ($covered/$($decisions.Count))." -ForegroundColor Green
exit 0

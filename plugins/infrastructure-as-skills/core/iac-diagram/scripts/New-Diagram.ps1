<#
.SYNOPSIS
    Draws an infra-spec.yaml as infra-diagram.drawio, with a computed layout.

.DESCRIPTION
    The layout is calculated, not hand-placed: every icon gets a fixed slot on a
    grid, containers are sized from their contents, and edges leave and enter at
    fixed sides. Two runs on the same spec produce the same file, and nothing
    overlaps by construction. The script still checks for overlaps afterwards and
    fails if it finds one - a layout rule that stopped holding is a bug here, not
    something to fix by hand in draw.io.

    Left to right:

      Internet | subscription > resource group > [ network | resources | observability ] | decisions

    Private endpoints sit in their subnet in one column, each on the same row as
    the resource it fronts, so the endpoint edge is a straight line. Role
    assignments loop out to the right of the resource column; diagnostics run
    right into the workspace. Referenced (existing) things are grey and dashed.

    Parsing needs a YAML reader, like Test-Spec.ps1: powershell-yaml, otherwise
    python with PyYAML. Without either it exits 2.

.PARAMETER Path
    The infra-spec.yaml to draw.

.PARAMETER OutFile
    The .drawio to write. Defaults to infra-diagram.drawio next to the spec.

.PARAMETER Language
    Language of the fixed labels and the decisions panel: de or en. Azure names,
    types, ranges and roles are never translated.

.EXAMPLE
    pwsh -NoProfile -File New-Diagram.ps1 ./infra-spec.yaml -Language de

.OUTPUTS
    Exit 0 written, 1 layout check failed or spec unreadable, 2 could not run.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string] $Path,

    [string] $OutFile,

    [ValidateSet('de', 'en')]
    [string] $Language = 'en'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    Write-Host "[skip] $Path not found." -ForegroundColor Yellow
    exit 2
}
$full = (Resolve-Path -LiteralPath $Path).Path
if (-not $OutFile) { $OutFile = Join-Path (Split-Path $full) 'infra-diagram.drawio' }

# --- Parse -----------------------------------------------------------------

function ConvertFrom-SpecYaml([string] $File) {
    if (Get-Module -ListAvailable -Name powershell-yaml) {
        Import-Module powershell-yaml -ErrorAction Stop
        return (Get-Content -LiteralPath $File -Raw | ConvertFrom-Yaml)
    }
    foreach ($py in @('python', 'python3', 'py')) {
        $exe = Get-Command $py -ErrorAction SilentlyContinue
        if (-not $exe) { continue }
        & $exe -c 'import yaml' 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { continue }
        $json = & $exe -c 'import sys,yaml,json;json.dump(yaml.safe_load(open(sys.argv[1],encoding="utf-8")),sys.stdout,default=str)' $File 2>&1
        if ($LASTEXITCODE -ne 0) { throw "YAML does not parse: $json" }
        return ($json | ConvertFrom-Json -AsHashtable)
    }
    throw 'NO_PARSER'
}

try {
    $spec = ConvertFrom-SpecYaml $full
} catch {
    if ($_.Exception.Message -eq 'NO_PARSER') {
        Write-Host '[skip] no YAML parser - Install-Module powershell-yaml, or pip install pyyaml' -ForegroundColor Yellow
        exit 2
    }
    Write-Host "[fail] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

function Get-At($map, [string[]] $keys) {
    $cur = $map
    foreach ($k in $keys) {
        if ($cur -isnot [System.Collections.IDictionary] -or -not $cur.Contains($k)) { return $null }
        $cur = $cur[$k]
    }
    return $cur
}
# A decision is either { value, source } or a bare value.
function Get-Value($node) {
    if ($node -is [System.Collections.IDictionary] -and $node.Contains('value')) { return $node['value'] }
    return $node
}
function Get-Decision($map, [string[]] $keys) { Get-Value (Get-At $map $keys) }

# A referenced resource is recorded as "name / resource-group". The name goes on
# the shape; the group goes to the panel, where text has room. Putting both on an
# icon label overflows its fixed slot.
function Split-Ref($value) {
    if ($null -eq $value) { return @{ name = $null; rg = $null } }
    $parts = "$value" -split '\s*/\s*', 2
    return @{ name = $parts[0]; rg = ($parts.Count -gt 1 ? $parts[1] : $null) }
}

# --- Labels ----------------------------------------------------------------

$T = @{
    en = @{
        internet = 'Internet'; noPublic = 'no public access'; existing = 'existing - not created'
        decisions = 'Decisions'; open = 'Open'; assumed = 'Assumed'; exposure = 'Exposure'
        network = 'Network'; mandates = 'Mandates'; dns = 'Private DNS'; diag = 'Diagnostics'
        forces = 'forces'; peSubnet = 'private endpoints'; owner = 'owner'
    }
    de = @{
        internet = 'Internet'; noPublic = 'kein öffentlicher Zugriff'; existing = 'vorhanden - wird nicht erstellt'
        decisions = 'Entscheidungen'; open = 'Offen'; assumed = 'Angenommen'; exposure = 'Erreichbarkeit'
        network = 'Netzwerk'; mandates = 'Vorgaben'; dns = 'Private DNS'; diag = 'Diagnose'
        forces = 'erzwingt'; peSubnet = 'Private Endpoints'; owner = 'zuständig'
    }
}[$Language]

# Every resource with a question set has a row. Paths verified against draw.io's
# azure2 library - a wrong path exports as a broken-image placeholder, silently.
$Icons = @{
    'subscription'            = 'img/lib/azure2/general/Subscriptions.svg'
    'resource-group'          = 'img/lib/azure2/general/Resource_Groups.svg'
    'storage-account'         = 'img/lib/azure2/storage/Storage_Accounts.svg'
    'virtual-network'         = 'img/lib/azure2/networking/Virtual_Networks.svg'
    'private-endpoint'        = 'img/lib/azure2/networking/Private_Endpoint.svg'
    'private-dns-zone'        = 'img/lib/azure2/networking/DNS_Zones.svg'
    'log-analytics-workspace' = 'img/lib/azure2/analytics/Log_Analytics_Workspaces.svg'
    'key-vault'               = 'img/lib/azure2/security/Key_Vaults.svg'
    'app-service'             = 'img/lib/azure2/app_services/App_Services.svg'
}
$TypeNames = @{
    'storage-account' = 'Storage Account'; 'virtual-network' = 'Virtual Network'
    'log-analytics-workspace' = 'Log Analytics Workspace'; 'key-vault' = 'Key Vault'
    'app-service' = 'App Service'
}

# --- Read the spec ---------------------------------------------------------

$ctx        = Get-At $spec @('context')
$dep        = Get-At $spec @('deployment')
$resources  = Get-At $spec @('resources')
if ($null -eq $resources) { $resources = @{} }

$exposure      = "$(Get-Decision $dep @('network_exposure'))"
$netOwnership  = "$(Get-Decision $dep @('network_ownership'))"
$obsOwnership  = "$(Get-Decision $dep @('observability_ownership'))"
$dnsOwnership  = "$(Get-Decision $dep @('private_dns_ownership'))"
$isPrivate     = $exposure -in @('private', 'private_with_exceptions')

$resKeys    = @($resources.Keys | Sort-Object)
$hasVnetRes = $resKeys -contains 'virtual-network'
$hasLawRes  = $resKeys -contains 'log-analytics-workspace'
$drawVnet   = $hasVnetRes -or $netOwnership -in @('create', 'reference')
$vnetExisting = (-not $hasVnetRes) -and $netOwnership -eq 'reference'

# Resources drawn in the middle column: everything that is not the network or the workspace.
$middle = @($resKeys | Where-Object { $_ -notin @('virtual-network', 'log-analytics-workspace') })

# Which resources get a private endpoint: an explicit subnet on the resource, or
# a private posture. The workspace is reached through AMPLS, not drawn here.
$withPe = @($middle | Where-Object {
    $isPrivate -or $null -ne (Get-Decision $resources[$_] @('networking', 'private_endpoint_subnet'))
})
$withoutPe = @($middle | Where-Object { $_ -notin $withPe })

$peSubnetName = (Split-Ref (Get-Decision $dep @('private_endpoint_subnet'))).name
$peSubnetPrefix = Get-Decision $dep @('private_endpoint_subnet_prefix')
if (-not $peSubnetName) { $peSubnetName = 'snet-' + $T.peSubnet.ToLower().Replace(' ', '') }

$otherSubnets = @()
foreach ($s in @(Get-Decision $resources['virtual-network'] @('addressing', 'subnets'))) {
    if ($null -eq $s) { continue }
    $name = if ($s -is [System.Collections.IDictionary]) { $s['name'] ?? $s['id'] } else { "$s" }
    $prefix = if ($s -is [System.Collections.IDictionary]) { $s['prefix'] ?? $s['address_prefix'] ?? (@($s['address_prefixes']) -join ', ') } else { '' }
    if ($name -and $name -ne $peSubnetName) { $otherSubnets += @{ name = $name; prefix = $prefix } }
}

$roles = @(Get-Decision $spec @('wiring', 'role_assignments') | Where-Object { $_ })
$zones = @(Get-Decision $spec @('wiring', 'private_dns_zones') | Where-Object { $_ })
$diagRef = Split-Ref (Get-Decision $dep @('diagnostics_destination'))
$diagTarget = $diagRef.name
$vnetRef = Split-Ref (Get-Decision $dep @('existing_vnet'))
$drawLaw = $hasLawRes -or $diagTarget

# assumed values anywhere in the spec, by dotted path
$assumed = [System.Collections.Generic.List[string]]::new()
function Find-Assumed($node, [string] $path) {
    if ($node -is [System.Collections.IDictionary]) {
        if ($node.Contains('source') -and "$($node['source'])" -eq 'assumed') { $assumed.Add($path) }
        foreach ($k in $node.Keys) { Find-Assumed $node[$k] ($path ? "$path.$k" : "$k") }
    }
}
Find-Assumed $spec ''
$open = @(Get-At $spec @('open') | Where-Object { $_ })

# A resource is flagged when an open or assumed entry points into it.
function Test-Flagged([string] $key) {
    foreach ($a in $assumed) { if ($a -like "resources.$key.*") { return $true } }
    foreach ($o in $open) { if ("$($o['key'])" -like "resources.$key.*") { return $true } }
    return $false
}

# --- Layout ----------------------------------------------------------------
# All geometry is absolute while laying out; the emitter converts children to
# coordinates relative to their container, which is what draw.io expects.

# A slot holds an icon and up to four label lines below it. The label is given
# the slot's width via labelWidth - without it draw.io wraps the label to the
# 48px image and breaks after every word.
$SLOT_W = 190; $SLOT_H = 130; $ICON = 48; $LABEL_W = $SLOT_W - 10
$HEAD = 44; $PAD = 20; $LANE_GAP = 120; $TRACK = 14

$cells = [System.Collections.Generic.List[hashtable]]::new()
function Add-Cell([hashtable] $c) { $cells.Add($c); return $c }

$containerStyle = 'rounded=0;whiteSpace=wrap;html=1;fillColor=none;strokeColor=#0078D4;verticalAlign=top;align=left;spacingLeft=36;spacingTop=4;fontStyle=1;container=1;collapsible=0;'
$existingStyle  = 'dashed=1;strokeColor=#999999;fontColor=#777777;'
$subnetStyle    = 'rounded=1;arcSize=4;whiteSpace=wrap;html=1;fillColor=#F3F9FD;strokeColor=#7FBAEA;verticalAlign=top;align=left;spacingLeft=10;spacingTop=2;container=1;collapsible=0;'
function Get-IconStyle([string] $img, [bool] $flagged, [bool] $existing) {
    $s = "image;aspect=fixed;html=1;points=[];align=center;verticalLabelPosition=bottom;verticalAlign=top;whiteSpace=wrap;labelWidth=$LABEL_W;image=$img;"
    if ($existing) { $s += 'opacity=60;fontColor=#777777;' }
    if ($flagged)  { $s += 'fontColor=#D13438;' }
    return $s
}

# One icon in a fixed slot: centred horizontally, label below inside the slot.
function Add-Icon([string] $id, [string] $parent, [double] $slotX, [double] $slotY, [string] $kind, [string] $label, [bool] $flagged = $false, [bool] $existing = $false) {
    $img = $Icons[$kind]
    if ($img) {
        $style = Get-IconStyle $img $flagged $existing
        $x = $slotX + ($SLOT_W - $ICON) / 2; $y = $slotY + 8; $w = $ICON; $h = $ICON
    } else {
        Write-Host "[warn] no icon for '$kind' - drawn as a box" -ForegroundColor Yellow
        # Same height and centre as an icon, so edges into it stay straight.
        $style = 'rounded=1;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#605E5C;'
        if ($flagged) { $style += 'fontColor=#D13438;' }
        $x = $slotX + 20; $y = $slotY + 8; $w = $SLOT_W - 40; $h = $ICON
    }
    Add-Cell @{ id = $id; parent = $parent; x = $x; y = $y; w = $w; h = $h; style = $style; value = $label; vertex = $true
                slot = @{ x = $slotX; y = $slotY; w = $SLOT_W; h = $SLOT_H }; labelBelow = [bool] $img } | Out-Null
}

function Format-Label([string] $title, [string] $sub, [string] $note) {
    $l = "<b>$([Security.SecurityElement]::Escape($title))</b>"
    if ($sub)  { $l += "<br><font style='font-size:10px'>$([Security.SecurityElement]::Escape($sub))</font>" }
    if ($note) { $l += "<br><font style='font-size:10px'><i>$([Security.SecurityElement]::Escape($note))</i></font>" }
    return $l
}

$internetW = if ($exposure -eq 'public') { 160 } else { 0 }
$subX = 20 + $internetW; $subY = 20
$rgX = $subX + $PAD;     $rgY = $subY + $HEAD
$laneY = $rgY + $HEAD + 10
$laneX = $rgX + $PAD

# Network lane
$rowY = @{}   # resource key -> absolute row y, shared by its endpoint and itself
$netRight = $laneX - $LANE_GAP
if ($drawVnet) {
    $vnX = $laneX; $vnY = $laneY
    $snX = $vnX + $PAD; $cursor = $vnY + $HEAD

    $peRows = [Math]::Max($withPe.Count, 1)
    $peSn = @{ x = $snX; y = $cursor; w = $SLOT_W + 2 * $PAD; h = 34 + $peRows * $SLOT_H + 10 }
    $i = 0
    foreach ($k in $withPe) { $rowY[$k] = $peSn.y + 34 + $i * $SLOT_H; $i++ }
    $cursor += $peSn.h + $PAD

    $otherBoxes = @()
    foreach ($s in $otherSubnets) {
        $otherBoxes += @{ name = $s.name; prefix = $s.prefix; x = $snX; y = $cursor; w = $peSn.w; h = 44 }
        $cursor += 44 + 10
    }
    $vnW = $peSn.w + 2 * $PAD
    $vnH = $cursor - $vnY + $PAD - ($otherBoxes.Count ? 10 : 0)
    $netRight = $vnX + $vnW
} else {
    $i = 0
    foreach ($k in $withPe) { $rowY[$k] = $laneY + $i * $SLOT_H; $i++ }
}

# Resource lane: endpoint-backed resources on their endpoint's row, the rest after.
$resX = $netRight + $LANE_GAP
$next = $laneY
if ($withPe.Count) { $next = ($withPe | ForEach-Object { $rowY[$_] } | Measure-Object -Maximum).Maximum + $SLOT_H }
foreach ($k in $withoutPe) { $rowY[$k] = $next; $next += $SLOT_H }
$resBottom = if ($middle.Count) { ($middle | ForEach-Object { $rowY[$_] } | Measure-Object -Maximum).Maximum + $SLOT_H } else { $laneY }
# Right of the resource column run vertical tracks: one per role assignment,
# then one shared by every diagnostics edge. Separate tracks are what keeps the
# lines from running on top of each other.
# The gap before the first track holds the role labels, which sit on each
# edge's last segment into its target.
$roleTrackX = $resX + $SLOT_W + ($roles.Count ? 50 : 0)
$diagTrackX = $roleTrackX + ($roles.Count + 1) * $TRACK
$resRight = if ($middle.Count) { $diagTrackX + $TRACK } else { $resX - $LANE_GAP }

# Observability lane: workspace on top, then the DNS zones.
$obsX = $resRight + $LANE_GAP
$obsY = if ($middle.Count) { ($middle | ForEach-Object { $rowY[$_] } | Measure-Object -Minimum).Minimum } else { $laneY }
$obsCount = ($drawLaw ? 1 : 0) + $zones.Count
$obsRight = if ($obsCount) { $obsX + $SLOT_W } else { $resRight }
$obsBottom = $obsY + $obsCount * $SLOT_H

$contentBottom = @($resBottom, $obsBottom, $laneY + $SLOT_H) | Measure-Object -Maximum | ForEach-Object Maximum
if ($drawVnet) { $contentBottom = [Math]::Max($contentBottom, $vnY + $vnH) }
$rgW = $obsRight + $PAD - $rgX
$rgH = $contentBottom + $PAD - $rgY + ($isPrivate ? 24 : 0)
$subW = $rgW + 2 * $PAD
$subH = $rgH + $HEAD + $PAD

# --- Cells -----------------------------------------------------------------

$subLabel = Format-Label 'Subscription' "$(Get-Value $ctx['subscription_id'])" ''
Add-Cell @{ id = 'sub'; parent = '1'; x = $subX; y = $subY; w = $subW; h = $subH; style = $containerStyle; value = $subLabel; vertex = $true } | Out-Null
Add-Cell @{ id = 'sub-icon'; parent = 'sub'; x = $subX + 6; y = $subY + 6; w = 24; h = 24; style = "image;aspect=fixed;html=1;image=$($Icons['subscription']);"; value = ''; vertex = $true } | Out-Null

$loc = "$(Get-Value $ctx['location'])"; $env_ = "$(Get-Value $ctx['environment'])"
$rgLabel = Format-Label "$(Get-Value $ctx['resource_group_name'] ?? 'resource group')" (@($loc, $env_) -ne '' -join ' · ') ''
Add-Cell @{ id = 'rg'; parent = 'sub'; x = $rgX; y = $rgY; w = $rgW; h = $rgH; style = $containerStyle; value = $rgLabel; vertex = $true } | Out-Null
Add-Cell @{ id = 'rg-icon'; parent = 'rg'; x = $rgX + 6; y = $rgY + 6; w = 24; h = 24; style = "image;aspect=fixed;html=1;image=$($Icons['resource-group']);"; value = ''; vertex = $true } | Out-Null

if ($isPrivate) {
    Add-Cell @{ id = 'rg-private'; parent = 'rg'; x = $rgX + $PAD; y = $rgY + $rgH - 26; w = $rgW - 2 * $PAD; h = 20
                style = 'text;html=1;align=left;verticalAlign=middle;fontColor=#107C10;fontStyle=2;'; value = "&#128274; $($T.noPublic)"; vertex = $true } | Out-Null
}

if ($drawVnet) {
    $vnName = if ($vnetExisting -and $vnetRef.name) { $vnetRef.name } else { 'Virtual Network' }
    $vnSub  = "$(Get-Decision $dep @('address_space') ?? (Get-Decision $resources['virtual-network'] @('addressing', 'address_space')))"
    $vnNote = if ($vnetExisting) { $T.existing } else { '' }
    $style  = $containerStyle + ($vnetExisting ? $existingStyle : '')
    Add-Cell @{ id = 'vnet'; parent = 'rg'; x = $vnX; y = $vnY; w = $vnW; h = $vnH; style = $style; value = (Format-Label $vnName $vnSub $vnNote); vertex = $true } | Out-Null
    Add-Cell @{ id = 'vnet-icon'; parent = 'vnet'; x = $vnX + 6; y = $vnY + 6; w = 24; h = 24; style = "image;aspect=fixed;html=1;image=$($Icons['virtual-network']);"; value = ''; vertex = $true } | Out-Null

    $peLabel = "<b>$([Security.SecurityElement]::Escape($peSubnetName))</b>" + ($peSubnetPrefix ? "  <font style='font-size:10px'>$peSubnetPrefix</font>" : '')
    Add-Cell @{ id = 'snet-pe'; parent = 'vnet'; x = $peSn.x; y = $peSn.y; w = $peSn.w; h = $peSn.h; style = $subnetStyle + ($vnetExisting ? $existingStyle : ''); value = $peLabel; vertex = $true } | Out-Null
    foreach ($k in $withPe) {
        Add-Icon "pe-$k" 'snet-pe' ($peSn.x + $PAD) $rowY[$k] 'private-endpoint' (Format-Label 'Private Endpoint' $k '')
    }
    $j = 0
    foreach ($b in $otherBoxes) {
        $lbl = "<b>$([Security.SecurityElement]::Escape($b.name))</b>" + ($b.prefix ? "  <font style='font-size:10px'>$($b.prefix)</font>" : '')
        Add-Cell @{ id = "snet-$j"; parent = 'vnet'; x = $b.x; y = $b.y; w = $b.w; h = $b.h; style = $subnetStyle; value = $lbl; vertex = $true } | Out-Null
        $j++
    }
}

foreach ($k in $middle) {
    $type = $TypeNames[$k] ?? $k
    Add-Icon "res-$k" 'rg' $resX $rowY[$k] $k (Format-Label $type $k '') (Test-Flagged $k) | Out-Null
}

$oy = $obsY
if ($drawLaw) {
    $lawExisting = (-not $hasLawRes) -and $obsOwnership -ne 'create'
    $lawName = if ($diagTarget) { "$diagTarget" } else { 'log-analytics-workspace' }
    Add-Icon 'law' 'rg' $obsX $oy 'log-analytics-workspace' (Format-Label 'Log Analytics' $lawName ($lawExisting ? $T.existing : '')) (Test-Flagged 'log-analytics-workspace') $lawExisting | Out-Null
    $oy += $SLOT_H
}
$z = 0
foreach ($zone in $zones) {
    $zExisting = $dnsOwnership -ne 'deployment'
    Add-Icon "dns-$z" 'rg' $obsX $oy 'private-dns-zone' (Format-Label "$zone" '' ($zExisting ? $T.existing : '')) $false $zExisting | Out-Null
    $oy += $SLOT_H; $z++
}

if ($exposure -eq 'public' -and $middle.Count) {
    $iy = ($middle | ForEach-Object { $rowY[$_] } | Measure-Object -Minimum).Minimum
    Add-Cell @{ id = 'internet'; parent = '1'; x = 30; y = $iy + 8 + $ICON / 2 - 30; w = 100; h = 60
                style = 'ellipse;shape=cloud;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#605E5C;'; value = $T.internet; vertex = $true } | Out-Null
}

# Decisions panel, right of the subscription.
$lines = [System.Collections.Generic.List[string]]::new()
function Add-Line([string] $html) { $lines.Add($html) }
function Esc($s) { [Security.SecurityElement]::Escape("$s") }
Add-Line "<b>$($T.decisions)</b>"
if ($exposure)     { Add-Line "$($T.exposure): <b>$(Esc $exposure)</b>" }
if ($netOwnership) { Add-Line "$($T.network): $(Esc $netOwnership)$(if ($vnSub) { ', ' + (Esc $vnSub) })" }
$mand = @(Get-Decision $dep @('mandates') | Where-Object { $_ })
if ($mand.Count)   { Add-Line "$($T.mandates): $(Esc ($mand -join ', '))" }
if ($dnsOwnership) { Add-Line "$($T.dns): $(Esc $dnsOwnership)" }
if ($diagTarget)   { Add-Line "$($T.diag): $(Esc $diagTarget)$(if ($diagRef.rg) { ' (' + (Esc $diagRef.rg) + ')' })" }
if ($vnetExisting -and $vnetRef.rg) { Add-Line "VNet: $(Esc $vnetRef.name) ($(Esc $vnetRef.rg))" }
# forced chains: deployment answers carrying `forces`
if ($dep -is [System.Collections.IDictionary]) {
    foreach ($k in $dep.Keys) {
        $f = Get-At $dep @($k, 'forces')
        foreach ($entry in @($f | Where-Object { $_ })) {
            $txt = if ($entry -is [System.Collections.IDictionary]) { ($entry.GetEnumerator() | ForEach-Object { "$($_.Key) = $($_.Value)" }) -join ', ' } else { "$entry" }
            Add-Line "<font color='#8A6100'>$(Esc $k): $(Esc (Get-Decision $dep @($k))) → $($T.forces) $(Esc $txt)</font>"
        }
    }
}
if ($open.Count) {
    Add-Line ''
    Add-Line "<b><font color='#D13438'>$($T.open)</font></b>"
    foreach ($o in $open) {
        $owner = if ($o['owner']) { " <i>($($T.owner): $(Esc $o['owner']))</i>" } else { '' }
        Add-Line "<font color='#D13438'>• $(Esc ($o['question'] ?? $o['key']))</font>$owner"
    }
}
if ($assumed.Count) {
    Add-Line ''
    Add-Line "<b><font color='#D13438'>$($T.assumed)</font></b>"
    foreach ($a in $assumed) { Add-Line "<font color='#D13438'>• $(Esc $a)</font>" }
}
$panelW = 340
# Rough wrap estimate: ~48 characters per line at 12px in 340px.
$panelLines = ($lines | ForEach-Object { [Math]::Max(1, [Math]::Ceiling(([regex]::Replace($_, '<[^>]+>', '')).Length / 48)) } | Measure-Object -Sum).Sum
$panelH = [Math]::Max(80, $panelLines * 18 + 24)
Add-Cell @{ id = 'panel'; parent = '1'; x = $subX + $subW + 40; y = $subY; w = $panelW; h = $panelH
            style = 'rounded=1;arcSize=3;whiteSpace=wrap;html=1;align=left;verticalAlign=top;spacing=12;fillColor=#F3F2F1;strokeColor=#C8C6C4;'
            value = ($lines -join '<br>'); vertex = $true } | Out-Null

# --- Edges -----------------------------------------------------------------

$byId = @{}; foreach ($c in $cells) { $byId[$c.id] = $c }
function Get-AnchorY([string] $id, [double] $fy) { $byId[$id].y + $byId[$id].h * $fy }

$edges = [System.Collections.Generic.List[hashtable]]::new()
$edgeBase = 'edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;endArrow=block;endFill=1;'
foreach ($k in $withPe) {
    if ($drawVnet) { $edges.Add(@{ id = "e-pe-$k"; source = "pe-$k"; target = "res-$k"; style = $edgeBase + 'exitX=1;exitY=0.5;entryX=0;entryY=0.5;strokeColor=#0078D4;'; value = '' }) }
}
$r = 0
foreach ($ra in $roles) {
    $from = "res-$($ra['from'])"; $to = "res-$($ra['to'])"
    if (-not $byId[$from] -or -not $byId[$to]) {
        Write-Host "[warn] role assignment $($ra['from']) -> $($ra['to']): endpoint not drawn" -ForegroundColor Yellow
        continue
    }
    $tx = $roleTrackX + ($r + 1) * $TRACK
    # The role name sits on the segment into the target: one per target row, so
    # two roles from the same principal do not stack on its shared stub.
    # Wrapped at ~18 characters to fit the gap.
    $wrapped = [System.Collections.Generic.List[string]]::new(); $line = ''
    foreach ($word in "$($ra['role'])" -split ' ') {
        if ($line -and ($line.Length + 1 + $word.Length) -gt 18) { $wrapped.Add($line); $line = $word }
        else { $line = ($line ? "$line $word" : $word) }
    }
    if ($line) { $wrapped.Add($line) }
    $edges.Add(@{ id = "e-role-$r"; source = $from; target = $to; value = (($wrapped | ForEach-Object { Esc $_ }) -join '<br>'); labelAt = 0.7
                  style = $edgeBase + "exitX=1;exitY=0.3;entryX=1;entryY=0.3;strokeColor=#5C2D91;fontColor=#5C2D91;fontSize=10;labelBackgroundColor=#FFFFFF;"
                  points = @(@{ x = $tx; y = (Get-AnchorY $from 0.3) }, @{ x = $tx; y = (Get-AnchorY $to 0.3) }) })
    $r++
}
if ($drawLaw) {
    $lawY = Get-AnchorY 'law' 0.5
    foreach ($k in $middle) {
        $edges.Add(@{ id = "e-diag-$k"; source = "res-$k"; target = 'law'; value = ''
                      style = $edgeBase + 'exitX=1;exitY=0.7;entryX=0;entryY=0.5;dashed=1;strokeColor=#8A8886;endArrow=open;'
                      points = @(@{ x = $diagTrackX; y = (Get-AnchorY "res-$k" 0.7) }, @{ x = $diagTrackX; y = $lawY }) })
    }
}
if ($exposure -eq 'public') {
    foreach ($k in $middle) {
        $edges.Add(@{ id = "e-inet-$k"; source = 'internet'; target = "res-$k"; value = ''
                      style = $edgeBase + 'exitX=1;exitY=0.5;entryX=0;entryY=0.5;strokeColor=#D83B01;' })
    }
}

# --- Overlap check ---------------------------------------------------------
# Siblings must not overlap. An icon is checked by its slot (icon + label), not
# by its 48px image, since the label is what collides first.

function Get-Box($c) { if ($c.slot) { $c.slot } else { @{ x = $c.x; y = $c.y; w = $c.w; h = $c.h } } }
$problems = @()
$byParent = $cells | Where-Object { $_.id -notlike '*-icon' -and $_.id -ne 'rg-private' } | Group-Object { $_.parent }
foreach ($g in $byParent) {
    $list = @($g.Group)
    for ($a = 0; $a -lt $list.Count; $a++) {
        for ($b = $a + 1; $b -lt $list.Count; $b++) {
            $p = Get-Box $list[$a]; $q = Get-Box $list[$b]
            if ($p.x -lt $q.x + $q.w -and $q.x -lt $p.x + $p.w -and $p.y -lt $q.y + $q.h -and $q.y -lt $p.y + $p.h) {
                $problems += "$($list[$a].id) overlaps $($list[$b].id)"
            }
        }
    }
}
# A label below an icon must end inside its slot. Estimated: ~26 characters
# per line at the slot's label width, 16px per line.
foreach ($c in $cells | Where-Object labelBelow) {
    $lineCount = 0
    foreach ($part in ($c.value -split '<br>')) {
        $plain = [regex]::Replace($part, '<[^>]+>', '')
        $lineCount += [Math]::Max(1, [Math]::Ceiling($plain.Length / 26))
    }
    if ($c.y + $c.h + 4 + $lineCount * 16 -gt $c.slot.y + $c.slot.h) {
        $problems += "$($c.id): label of $lineCount lines does not fit its slot"
    }
}
# Children must fit inside their container.
foreach ($c in $cells) {
    if ($c.parent -eq '1') { continue }
    $p = $byId[$c.parent]; $box = Get-Box $c
    if ($box.x -lt $p.x -or $box.y -lt $p.y -or $box.x + $box.w -gt $p.x + $p.w -or $box.y + $box.h -gt $p.y + $p.h) {
        $problems += "$($c.id) leaves its container $($c.parent)"
    }
}
if ($problems) {
    $problems | ForEach-Object { Write-Host "[fail] $_" -ForegroundColor Red }
    exit 1
}

# --- Emit ------------------------------------------------------------------

function Attr($s) { [Security.SecurityElement]::Escape("$s") }
$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine('<mxfile host="infrastructure-as-skills">')
[void]$sb.AppendLine("  <diagram id=`"infra`" name=`"$(Attr ($spec.spec.id ?? 'infra'))`">")
[void]$sb.AppendLine('    <mxGraphModel grid="1" gridSize="10" page="0" math="0" shadow="0">')
[void]$sb.AppendLine('      <root>')
[void]$sb.AppendLine('        <mxCell id="0"/>')
[void]$sb.AppendLine('        <mxCell id="1" parent="0"/>')
foreach ($c in $cells) {
    $px = 0; $py = 0
    if ($c.parent -ne '1') { $px = $byId[$c.parent].x; $py = $byId[$c.parent].y }
    [void]$sb.AppendLine("        <mxCell id=`"$($c.id)`" value=`"$(Attr $c.value)`" style=`"$(Attr $c.style)`" vertex=`"1`" parent=`"$($c.parent)`">")
    [void]$sb.AppendLine("          <mxGeometry x=`"$($c.x - $px)`" y=`"$($c.y - $py)`" width=`"$($c.w)`" height=`"$($c.h)`" as=`"geometry`"/>")
    [void]$sb.AppendLine('        </mxCell>')
}
foreach ($e in $edges) {
    [void]$sb.AppendLine("        <mxCell id=`"$($e.id)`" value=`"$(Attr $e.value)`" style=`"$(Attr $e.style)`" edge=`"1`" parent=`"1`" source=`"$($e.source)`" target=`"$($e.target)`">")
    if ($e.points) {
        # Waypoints are absolute, since every edge's parent is the root layer.
        $pts = ($e.points | ForEach-Object { "<mxPoint x=`"$($_.x)`" y=`"$($_.y)`"/>" }) -join ''
        $labelPos = if ($e.labelAt) { " x=`"$($e.labelAt)`"" } else { '' }
        # A label rides above its segment rather than on it, so it never covers the arrowhead.
        $offset = if ($e.labelAt) { '<mxPoint y="-16" as="offset"/>' } else { '' }
        [void]$sb.AppendLine("          <mxGeometry relative=`"1`"$labelPos as=`"geometry`"><Array as=`"points`">$pts</Array>$offset</mxGeometry>")
    } else {
        [void]$sb.AppendLine('          <mxGeometry relative="1" as="geometry"/>')
    }
    [void]$sb.AppendLine('        </mxCell>')
}
[void]$sb.AppendLine('      </root>')
[void]$sb.AppendLine('    </mxGraphModel>')
[void]$sb.AppendLine('  </diagram>')
[void]$sb.AppendLine('</mxfile>')

Set-Content -LiteralPath $OutFile -Value $sb.ToString() -Encoding utf8NoBOM
Write-Host "[ ok ] $OutFile - $($cells.Count) shapes, $($edges.Count) edges, no overlaps" -ForegroundColor Green
exit 0

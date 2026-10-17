<#
.SYNOPSIS
    Exports an infra-diagram.drawio to infra-diagram.drawio.png with the diagram
    embedded, so the PNG opens as an editable diagram in draw.io.

.DESCRIPTION
    Uses the draw.io desktop CLI. Looks for it on PATH (drawio, draw.io), then in
    the default install locations on Windows, macOS and Linux.

    Clears ELECTRON_RUN_AS_NODE for the call. VS Code sets it for its own child
    processes, and with it set draw.io starts as plain Node and rejects every
    export flag as a "bad option".

    Without draw.io the script exits 2 and leaves the .drawio file in place. That
    file is the diagram; the PNG is a convenience, and a missing exporter is said
    out loud rather than papered over.

.PARAMETER Path
    The .drawio file to export.

.PARAMETER OutFile
    The PNG to write. Defaults to <Path>.png, i.e. infra-diagram.drawio.png.

.PARAMETER NoEmbed
    Write a plain PNG without the diagram inside. For a visual check only, never
    for the deliverable.

.EXAMPLE
    pwsh -NoProfile -File Export-Diagram.ps1 ./infra-diagram.drawio
    pwsh -NoProfile -File Export-Diagram.ps1 ./infra-diagram.drawio -OutFile ./preview.png -NoEmbed

.OUTPUTS
    Exit 0 written, 1 export failed, 2 could not export (no file, no draw.io).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string] $Path,

    [string] $OutFile,

    [switch] $NoEmbed
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    Write-Host "[skip] $Path not found." -ForegroundColor Yellow
    exit 2
}
$Path = (Resolve-Path -LiteralPath $Path).Path
if (-not $OutFile) { $OutFile = "$Path.png" }

$candidates = @(
    (Get-Command drawio -ErrorAction SilentlyContinue).Source
    (Get-Command draw.io -ErrorAction SilentlyContinue).Source
    if ($env:ProgramFiles) { Join-Path $env:ProgramFiles 'draw.io\draw.io.exe' }
    if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Programs\draw.io\draw.io.exe' }
    '/Applications/draw.io.app/Contents/MacOS/draw.io'
    '/usr/bin/drawio'
    '/opt/drawio/drawio'
) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) }

$drawio = $candidates | Select-Object -First 1
if (-not $drawio) {
    Write-Host '[skip] draw.io desktop not found - the .drawio file is the deliverable.' -ForegroundColor Yellow
    Write-Host '       Install it from https://www.drawio.com or open the file at app.diagrams.net.'
    exit 2
}

$saved = $env:ELECTRON_RUN_AS_NODE
try {
    $env:ELECTRON_RUN_AS_NODE = $null
    # --embed-diagram keeps the XML inside the PNG; --scale 2 keeps it legible
    # when pasted into a document.
    $exportArgs = @('--export', '--format', 'png', '--scale', '2', '--border', '20')
    if (-not $NoEmbed) { $exportArgs += '--embed-diagram' }
    & $drawio @exportArgs --output $OutFile $Path 2>&1 | Out-Null
} finally {
    $env:ELECTRON_RUN_AS_NODE = $saved
}

if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $OutFile)) {
    Write-Host "[fail] draw.io exited $LASTEXITCODE, no PNG written." -ForegroundColor Red
    exit 1
}

Write-Host "[ ok ] $OutFile" -ForegroundColor Green
exit 0

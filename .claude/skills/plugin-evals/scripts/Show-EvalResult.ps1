<#
.SYNOPSIS
    Summarises a `claude plugin eval --json` result: per case, per run, every
    grader's verdict - failures first, with the explanation.

.DESCRIPTION
    Read-only. The HTML report is for browsing; this is for the question that
    matters after a run - which decisions failed, in how many of the runs, and
    why. A grader that fails in some runs but not all is flagged as unstable:
    that is a decision the plugin does not pin down, and the first thing to read.

    A run that errored before the agent started (turns = 0) is reported as a
    harness error, not as grader failures - its graders never saw any output.

.PARAMETER Path
    The JSON written by `claude plugin eval --json <path>`, or an
    aggregate-result.json from evals/results/<timestamp>/.

.PARAMETER All
    Also list passing graders.

.EXAMPLE
    pwsh -NoProfile -File Show-EvalResult.ps1 ./eval-run.json

.OUTPUTS
    Exit 0 every case passed, 1 a case failed, 2 a run errored or the file is unreadable.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string] $Path,

    [switch] $All
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    Write-Host "[skip] $Path not found." -ForegroundColor Yellow
    exit 2
}
$result = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable

$agg = $result.aggregates
Write-Host ("Eval {0} - {1}/{2} case(s) passed, score {3:P0}, {4:N0}s, `${5:N2}" -f `
    $result.startedAt, $agg.casesPassed, $agg.casesTotal, $agg.overallScore, $result.durationSeconds, $result.costUsd) -ForegroundColor Cyan
Write-Host ('-' * 70)

$harnessErrors = 0
foreach ($case in $result.cases) {
    $runs = @($case.arms.with)
    Write-Host ("{0}  score {1:P0}  ({2} run(s))" -f $case.name, $case.aggregates.score, $runs.Count) -ForegroundColor White

    $errored = @($runs | Where-Object { $_.error -and $_.turns -eq 0 })
    foreach ($r in $errored) {
        $harnessErrors++
        Write-Host "  [harness] run never started: $(($r.error -split ' · ')[0])" -ForegroundColor Magenta
    }
    $scoredRuns = @($runs | Where-Object { $_ -notin $errored })
    if ($scoredRuns.Count -eq 0) { continue }

    foreach ($r in $scoredRuns | Where-Object error) {
        Write-Host "  [run error] $(($r.error -split ' · ')[0])  (turns: $($r.turns))" -ForegroundColor Magenta
    }

    # Per grader across runs: n passed of m.
    $names = @($case.graders | ForEach-Object name)
    foreach ($name in $names) {
        $verdicts = @($scoredRuns | ForEach-Object { $_.graders | Where-Object name -eq $name })
        $passed = @($verdicts | Where-Object passed).Count
        $total = $verdicts.Count
        $indicator = ($verdicts | Select-Object -First 1).scored -eq $false

        $state, $color = if ($passed -eq $total) { 'pass', 'Green' }
                         elseif ($passed -eq 0) { 'FAIL', 'Red' }
                         else { 'UNSTABLE', 'Yellow' }
        if ($state -eq 'pass' -and -not $All) { continue }

        $tag = if ($indicator) { ' (indicator)' } else { '' }
        Write-Host ("  [{0,-8}] {1} {2}/{3}{4}" -f $state, $name, $passed, $total, $tag) -ForegroundColor $color
        foreach ($v in $verdicts | Where-Object { -not $_.passed } | Select-Object -First 1) {
            Write-Host "             $($v.explanation)" -ForegroundColor DarkGray
        }
    }
    foreach ($r in $scoredRuns | Where-Object tracePath) {
        Write-Host "  trace: $($r.tracePath)" -ForegroundColor DarkGray
    }
}

if ($harnessErrors) { exit 2 }
if ($agg.casesPassed -lt $agg.casesTotal) { exit 1 }
exit 0

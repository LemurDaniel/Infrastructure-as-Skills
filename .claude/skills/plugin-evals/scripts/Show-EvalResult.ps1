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

.PARAMETER Baseline
    The committed snapshot of the last accepted run, per case and grader:
    passed of total. Defaults to evals/baseline.json in the plugin. When it
    exists, every grader is compared against it and a lower pass rate is
    reported as REGRESS - the run is then a failure even if every case still
    passes on aggregate, because a decision the plugin used to pin down has
    come loose. A grader or case absent from the baseline is reported as new.

.PARAMETER UpdateBaseline
    Write this run's pass rates to -Baseline instead of comparing. Do it after
    reading the run and accepting it, never automatically: the baseline is the
    memory the next run is judged against, and a bad run written into it hides
    the regression it carries.

.EXAMPLE
    pwsh -NoProfile -File Show-EvalResult.ps1 ./eval-run.json
    pwsh -NoProfile -File Show-EvalResult.ps1 ./eval-run.json -UpdateBaseline

.OUTPUTS
    Exit 0 every case passed and nothing regressed, 1 a case failed or a grader
    regressed against the baseline, 2 a run errored or the file is unreadable.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string] $Path,

    [switch] $All,

    [string] $Baseline = (Join-Path $PSScriptRoot '..' '..' '..' '..' 'plugins' 'infrastructure-as-skills' 'evals' 'baseline.json'),

    [switch] $UpdateBaseline
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    Write-Host "[skip] $Path not found." -ForegroundColor Yellow
    exit 2
}
$result = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable

$baselineData = $null
if (-not $UpdateBaseline -and (Test-Path -LiteralPath $Baseline -PathType Leaf)) {
    $baselineData = Get-Content -LiteralPath $Baseline -Raw | ConvertFrom-Json -AsHashtable
}
# This run's pass rates, collected while printing; written out under -UpdateBaseline.
$snapshot = [ordered]@{
    startedAt = $result.startedAt
    cases     = [ordered]@{}
}
$regressions = 0

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
    $caseSnapshot = [ordered]@{}
    $snapshot.cases[$case.name] = $caseSnapshot
    $baseCase = if ($baselineData) { $baselineData.cases[$case.name] } else { $null }

    $names = @($case.graders | ForEach-Object name)
    foreach ($name in $names) {
        $verdicts = @($scoredRuns | ForEach-Object { $_.graders | Where-Object name -eq $name })
        $passed = @($verdicts | Where-Object passed).Count
        $total = $verdicts.Count
        $indicator = ($verdicts | Select-Object -First 1).scored -eq $false
        $caseSnapshot[$name] = [ordered]@{ passed = $passed; total = $total }

        $state, $color = if ($passed -eq $total) { 'pass', 'Green' }
                         elseif ($passed -eq 0) { 'FAIL', 'Red' }
                         else { 'UNSTABLE', 'Yellow' }

        # Against the baseline: a lower rate is a regression whatever the state,
        # a higher one is worth a line, and a grader the baseline never saw is new.
        $delta = ''
        if ($baselineData) {
            $prev = if ($baseCase) { $baseCase[$name] } else { $null }
            if ($null -eq $prev) {
                $delta = ' (new: not in baseline)'
            } elseif ($prev.total -gt 0 -and $total -gt 0) {
                $prevRate = $prev.passed / $prev.total
                $rate = $passed / $total
                if ($rate -lt $prevRate) {
                    $regressions++
                    $state, $color = 'REGRESS', 'Magenta'
                    $delta = " (baseline $($prev.passed)/$($prev.total))"
                } elseif ($rate -gt $prevRate) {
                    $delta = " (improved from $($prev.passed)/$($prev.total))"
                }
            }
        }
        if ($state -eq 'pass' -and -not $All -and -not $delta) { continue }

        $tag = if ($indicator) { ' (indicator)' } else { '' }
        Write-Host ("  [{0,-8}] {1} {2}/{3}{4}{5}" -f $state, $name, $passed, $total, $tag, $delta) -ForegroundColor $color
        foreach ($v in $verdicts | Where-Object { -not $_.passed } | Select-Object -First 1) {
            Write-Host "             $($v.explanation)" -ForegroundColor DarkGray
        }
    }
    foreach ($r in $scoredRuns | Where-Object tracePath) {
        Write-Host "  trace: $($r.tracePath)" -ForegroundColor DarkGray
    }
}

if ($UpdateBaseline) {
    if ($harnessErrors) {
        Write-Host "[skip] baseline not written - a run errored, so these rates are not a measurement." -ForegroundColor Yellow
    } else {
        $snapshot | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Baseline -Encoding utf8
        Write-Host "[ ok ] baseline written to $Baseline" -ForegroundColor Green
    }
} elseif ($baselineData) {
    Write-Host ('-' * 70)
    if ($regressions) {
        Write-Host "[fail] $regressions grader(s) regressed against the baseline from $($baselineData.startedAt)" -ForegroundColor Magenta
    } else {
        Write-Host "[ ok ] nothing regressed against the baseline from $($baselineData.startedAt)" -ForegroundColor Green
    }
} else {
    Write-Host "[note] no baseline at $Baseline - accept this run with -UpdateBaseline to create one." -ForegroundColor DarkGray
}

if ($harnessErrors) { exit 2 }
if ($agg.casesPassed -lt $agg.casesTotal) { exit 1 }
if ($regressions) { exit 1 }
exit 0

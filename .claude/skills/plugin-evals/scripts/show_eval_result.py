#!/usr/bin/env python3
"""Summarises a `claude plugin eval --json` result: per case, per run, every
grader's verdict - failures first, with the explanation.

Read-only. The HTML report is for browsing; this is for the question that
matters after a run - which decisions failed, in how many of the runs, and
why. A grader that fails in some runs but not all is flagged as unstable:
that is a decision the plugin does not pin down, and the first thing to read.

A run that errored before the agent started (turns = 0) is reported as a
harness error, not as grader failures - its graders never saw any output.

The baseline (--baseline, default evals/baseline.json in the plugin) is the
committed snapshot of the last accepted run, per case and grader: passed of
total. When it exists, every grader is compared against it and a lower pass
rate is reported as REGRESS - the run is then a failure even if every case
still passes on aggregate, because a decision the plugin used to pin down has
come loose. A grader or case absent from the baseline is reported as new.

--update-baseline writes this run's pass rates to the baseline instead of
comparing. Do it after reading the run and accepting it, never automatically:
the baseline is the memory the next run is judged against, and a bad run
written into it hides the regression it carries.

Usage:
    python3 show_eval_result.py ./eval-run.json
    python3 show_eval_result.py ./eval-run.json --update-baseline

Exit 0 every case passed and nothing regressed, 1 a case failed or a grader
regressed against the baseline, 2 a run errored or the file is unreadable.
"""

import argparse
import json
import os
import sys

COLORS = {'cyan': '36', 'green': '32', 'red': '31', 'yellow': '33', 'gray': '90', 'magenta': '35', 'white': '97'}
USE_COLOR = sys.stdout.isatty() and not os.environ.get('NO_COLOR')

DEFAULT_BASELINE = os.path.normpath(os.path.join(
    os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', '..',
    'plugins', 'infrastructure-as-skills-azure', 'evals', 'baseline.json'))


def say(text, color=None):
    if color and USE_COLOR:
        print(f"\033[{COLORS[color]}m{text}\033[0m")
    else:
        print(text)


def first_part(error):
    return str(error).split(' · ')[0]


def main():
    ap = argparse.ArgumentParser(description='Summarise a claude plugin eval --json result.')
    ap.add_argument('path', help='the JSON written by `claude plugin eval --json <path>`, or an aggregate-result.json')
    ap.add_argument('--all', action='store_true', help='also list passing graders')
    ap.add_argument('--baseline', default=DEFAULT_BASELINE, help='the committed snapshot of the last accepted run')
    ap.add_argument('--update-baseline', action='store_true', help="write this run's pass rates to the baseline instead of comparing")
    args = ap.parse_args()

    if not os.path.isfile(args.path):
        say(f"[skip] {args.path} not found.", 'yellow')
        return 2
    with open(args.path, encoding='utf-8') as f:
        result = json.load(f)

    baseline = None
    if not args.update_baseline and os.path.isfile(args.baseline):
        with open(args.baseline, encoding='utf-8') as f:
            baseline = json.load(f)
    # This run's pass rates, collected while printing; written out under --update-baseline.
    snapshot = {'startedAt': result.get('startedAt'), 'cases': {}}
    regressions = 0

    agg = result.get('aggregates') or {}
    say("Eval {} - {}/{} case(s) passed, score {:.0%}, {:,.0f}s, ${:,.2f}".format(
        result.get('startedAt'), agg.get('casesPassed', 0), agg.get('casesTotal', 0),
        agg.get('overallScore') or 0, result.get('durationSeconds') or 0, result.get('costUsd') or 0), 'cyan')
    print('-' * 70)

    harness_errors = 0
    for case in result.get('cases') or []:
        runs = list(((case.get('arms') or {}).get('with')) or [])
        say("{}  score {:.0%}  ({} run(s))".format(case.get('name'), (case.get('aggregates') or {}).get('score') or 0, len(runs)), 'white')

        errored = [r for r in runs if r.get('error') and r.get('turns') == 0]
        for r in errored:
            harness_errors += 1
            say(f"  [harness] run never started: {first_part(r['error'])}", 'magenta')
        scored = [r for r in runs if r not in errored]
        if not scored:
            continue

        for r in scored:
            if r.get('error'):
                say(f"  [run error] {first_part(r['error'])}  (turns: {r.get('turns')})", 'magenta')

        # Per grader across runs: n passed of m.
        case_snapshot = {}
        snapshot['cases'][case.get('name')] = case_snapshot
        base_case = (baseline.get('cases') or {}).get(case.get('name')) if baseline else None

        names = [g.get('name') for g in (case.get('graders') or [])]
        for name in names:
            verdicts = [g for r in scored for g in (r.get('graders') or []) if g.get('name') == name]
            passed = sum(1 for v in verdicts if v.get('passed'))
            total = len(verdicts)
            indicator = bool(verdicts) and verdicts[0].get('scored') is False
            case_snapshot[name] = {'passed': passed, 'total': total}

            if passed == total:
                state, color = 'pass', 'green'
            elif passed == 0:
                state, color = 'FAIL', 'red'
            else:
                state, color = 'UNSTABLE', 'yellow'

            # Against the baseline: a lower rate is a regression whatever the state,
            # a higher one is worth a line, and a grader the baseline never saw is new.
            delta = ''
            if baseline:
                prev = base_case.get(name) if base_case else None
                if prev is None:
                    delta = ' (new: not in baseline)'
                elif prev.get('total', 0) > 0 and total > 0:
                    prev_rate = prev['passed'] / prev['total']
                    rate = passed / total
                    if rate < prev_rate:
                        regressions += 1
                        state, color = 'REGRESS', 'magenta'
                        delta = f" (baseline {prev['passed']}/{prev['total']})"
                    elif rate > prev_rate:
                        delta = f" (improved from {prev['passed']}/{prev['total']})"
            if state == 'pass' and not args.all and not delta:
                continue

            tag = ' (indicator)' if indicator else ''
            say(f"  [{state:<8}] {name} {passed}/{total}{tag}{delta}", color)
            for v in verdicts:
                if not v.get('passed'):
                    say(f"             {v.get('explanation')}", 'gray')
                    break
        for r in scored:
            if r.get('tracePath'):
                say(f"  trace: {r['tracePath']}", 'gray')

    if args.update_baseline:
        if harness_errors:
            say('[skip] baseline not written - a run errored, so these rates are not a measurement.', 'yellow')
        else:
            with open(args.baseline, 'w', encoding='utf-8') as f:
                json.dump(snapshot, f, indent=2)
                f.write('\n')
            say(f"[ ok ] baseline written to {args.baseline}", 'green')
    elif baseline:
        print('-' * 70)
        if regressions:
            say(f"[fail] {regressions} grader(s) regressed against the baseline from {baseline.get('startedAt')}", 'magenta')
        else:
            say(f"[ ok ] nothing regressed against the baseline from {baseline.get('startedAt')}", 'green')
    else:
        say(f"[note] no baseline at {args.baseline} - accept this run with --update-baseline to create one.", 'gray')

    if harness_errors:
        return 2
    if agg.get('casesPassed', 0) < agg.get('casesTotal', 0):
        return 1
    if regressions:
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())

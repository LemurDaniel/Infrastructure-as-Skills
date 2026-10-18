#!/usr/bin/env python3
"""Runs the Bicep render's tests: compiles the template and checks every
assertion in tests/*.armtest.yaml against the compiled ARM JSON.

The Bicep counterpart of `terraform test` for this plugin. A Terraform render
asserts on the plan; a Bicep render has no plan without a subscription, but
`bicep build` is deterministic and the compiled template carries every
decision as a literal - a module parameter value, a resource property - or
as an ARM expression whose text still names the literal. The assertions
read that JSON.

The test file is a list. One entry per spec decision, either an assertion
or a marker, mirroring the Terraform markers that check_render_coverage.py
counts:

    - decision: storage-account.networking.public_network_access
      path: resources.storageAccount.properties.parameters.publicNetworkAccess.value
      equals: Disabled

    - decision: virtual-network.addressing.subnets
      path: resources.virtualNetwork.properties.parameters.subnets.value
      matches: '10\\.20\\.2\\.0/24'

    - not_testable: log-analytics-workspace.data_protection.immediate_purge_protection
      reason: a deletion-time query parameter, not a template property

An entry may also carry `deployment: <key>` or `wiring: <key>` instead of
`decision:` for a deployment-level or wiring assertion; coverage ignores
those, the runner evaluates them.

An entry with `stage: <name>` is evaluated against that stage's parameter
file instead - `bicep/main.<stage>.bicepparam`, compiled with
`bicep build-params` - with `path` from the parameters root
(`parameters.addressSpace.value`). That is how a per-stage value is
asserted: as the stage file's value, never as a literal in the template.

`path` is dotted, with `[n]` for a list index, from the template root. One
operator per entry:

    equals:  <value>    the JSON value at path, compared as parsed YAML
    contains: <value>   a list holds the value, or a string holds the substring
    matches: <regex>    searched in the JSON dump of the value at path -
                        for values the compiler turned into expressions
    absent: true        nothing at path

Symbolic resource names (`resources.<name>`) need the template compiled with
languageVersion 2.0. A `bicepconfig.json` beside the template with
`"experimentalFeaturesEnabled": { "symbolicNameCodegen": true }` forces it;
without it, resources is a list and the script says so.

Needs the bicep CLI on PATH and PyYAML.

Usage:
    python3 run_arm_tests.py ./infra-spec.yaml [--template bicep/main.bicep] [--tests tests]

Exit 0 every assertion holds, 1 a failure, 2 could not run.
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys

COLORS = {'cyan': '36', 'green': '32', 'red': '31', 'gray': '90', 'yellow': '33'}
USE_COLOR = sys.stdout.isatty() and not os.environ.get('NO_COLOR')


def say(text, color=None):
    if color and USE_COLOR:
        print(f"\033[{COLORS[color]}m{text}\033[0m")
    else:
        print(text)


def ok(text): say(f"[ ok ] {text}", 'green')
def bad(text): say(f"[fail] {text}", 'red')
def warn(text): say(f"[warn] {text}", 'yellow')


MISSING = object()
TOKEN_RE = re.compile(r'([^.\[\]]+)|\[(\d+)\]')


def resolve(doc, path):
    """Walk a dotted path with [n] indexes. Returns MISSING when it leads nowhere."""
    node = doc
    for key, idx in TOKEN_RE.findall(path):
        if idx != '':
            if not isinstance(node, list) or int(idx) >= len(node):
                return MISSING
            node = node[int(idx)]
        else:
            if not isinstance(node, dict) or key not in node:
                return MISSING
            node = node[key]
    return node


def evaluate(entry, template):
    """Returns None when the assertion holds, else the failure text."""
    path = entry.get('path')
    if not path:
        return 'no path'
    value = resolve(template, path)
    ops = [k for k in ('equals', 'contains', 'matches', 'absent') if k in entry]
    if len(ops) != 1:
        return f"exactly one of equals / contains / matches / absent, got {ops}"
    op = ops[0]
    if op == 'absent':
        return None if value is MISSING else f"expected nothing at {path}, found {json.dumps(value)[:120]}"
    if value is MISSING:
        return f"nothing at {path}"
    if op == 'equals':
        return None if value == entry['equals'] else f"{path} is {json.dumps(value)[:200]}, expected {json.dumps(entry['equals'])}"
    if op == 'contains':
        want = entry['contains']
        if isinstance(value, list):
            return None if want in value else f"{path} does not contain {json.dumps(want)}: {json.dumps(value)[:200]}"
        if isinstance(value, str):
            return None if str(want) in value else f"{path} does not contain {want!r}: {value[:200]}"
        return f"{path} is neither a list nor a string"
    if op == 'matches':
        dump = json.dumps(value)
        return None if re.search(entry['matches'], dump) else f"{path} does not match /{entry['matches']}/: {dump[:200]}"
    return 'unreachable'


def main():
    ap = argparse.ArgumentParser(description="Run a Bicep render's tests against its compiled ARM.")
    ap.add_argument('spec', help='the infra-spec.yaml; the template and tests are looked up beside it')
    ap.add_argument('--template', help='the Bicep root to compile (default: <spec dir>/bicep/main.bicep)')
    ap.add_argument('--tests', help='directory holding the .armtest.yaml files (default: <spec dir>/tests)')
    args = ap.parse_args()

    if not os.path.isfile(args.spec):
        bad(f"no such file: {args.spec}")
        return 2
    base = os.path.dirname(os.path.abspath(args.spec))
    template = args.template or os.path.join(base, 'bicep', 'main.bicep')
    tests_dir = args.tests or os.path.join(base, 'tests')
    if not os.path.isfile(template):
        bad(f"no template at {template}")
        return 2
    files = sorted(f for f in os.listdir(tests_dir) if f.endswith('.armtest.yaml')) if os.path.isdir(tests_dir) else []
    if not files:
        bad(f"no .armtest.yaml in {tests_dir} - a render without tests is not finished")
        return 1

    try:
        import yaml
    except ImportError:
        bad('no YAML parser available (pip install pyyaml)')
        return 2
    bicep = shutil.which('bicep')
    if not bicep:
        bad('bicep is not on PATH')
        return 2

    say(f"ARM tests - {template}", 'cyan')
    print('-' * 70)
    proc = subprocess.run([bicep, 'build', '--stdout', template], capture_output=True, text=True)
    if proc.returncode != 0:
        bad('bicep build failed')
        say(proc.stderr.strip(), 'gray')
        return 1
    try:
        compiled = json.loads(proc.stdout)
    except json.JSONDecodeError as e:
        bad(f"bicep build produced no JSON: {e}")
        return 1
    if isinstance(compiled.get('resources'), list):
        bad('the compiled template has no symbolic resource names (languageVersion 2.0)')
        say('       Put a bicepconfig.json beside the template with', 'gray')
        say('         { "experimentalFeaturesEnabled": { "symbolicNameCodegen": true } }', 'gray')
        return 2
    ok(f"compiled - languageVersion {compiled.get('languageVersion')}, resources: {', '.join(compiled['resources'])}")

    stage_params = {}

    def params_of(stage):
        if stage in stage_params:
            return stage_params[stage]
        pfile = os.path.join(os.path.dirname(template), f"main.{stage}.bicepparam")
        if not os.path.isfile(pfile):
            stage_params[stage] = None
            return None
        p = subprocess.run([bicep, 'build-params', pfile, '--stdout'], capture_output=True, text=True)
        if p.returncode != 0:
            bad(f"bicep build-params failed for {pfile}")
            say(p.stderr.strip(), 'gray')
            stage_params[stage] = None
            return None
        try:
            stage_params[stage] = json.loads(json.loads(p.stdout)['parametersJson'])
            ok(f"stage {stage} - {os.path.basename(pfile)} compiled")
        except (json.JSONDecodeError, KeyError) as e:
            bad(f"{pfile}: no parameters JSON: {e}")
            stage_params[stage] = None
        return stage_params[stage]

    total, failures, marked = 0, [], 0
    for f in files:
        with open(os.path.join(tests_dir, f), encoding='utf-8') as fh:
            try:
                entries = yaml.safe_load(fh) or []
            except yaml.YAMLError as e:
                bad(f"{f}: YAML does not parse: {e}")
                return 1
        if not isinstance(entries, list):
            bad(f"{f}: the test file is a list of entries")
            return 1
        for i, entry in enumerate(entries, 1):
            if not isinstance(entry, dict):
                failures.append(f"{f}#{i}: not a mapping")
                continue
            if 'not_testable' in entry:
                marked += 1
                if not str(entry.get('reason', '')).strip():
                    failures.append(f"{f}#{i}: not_testable {entry['not_testable']} has no reason")
                continue
            label = entry.get('decision') or entry.get('deployment') or entry.get('wiring') or f"{f}#{i}"
            total += 1
            stage = entry.get('stage')
            if stage:
                label = f"{label} [{stage}]"
                doc = params_of(str(stage))
                problem = f"no parameter file for stage '{stage}' (bicep/main.{stage}.bicepparam)" if doc is None else evaluate(entry, doc)
            else:
                problem = evaluate(entry, compiled)
            if problem:
                failures.append(f"{label}: {problem}")
    print('-' * 70)
    if failures:
        bad(f"{len(failures)} failure(s) out of {total} assertion(s)")
        for x in failures:
            say(f"         {x}", 'gray')
        return 1
    say(f"{total} assertion(s) hold, {marked} decision(s) marked not-testable with a reason.", 'green')
    return 0


if __name__ == '__main__':
    sys.exit(main())

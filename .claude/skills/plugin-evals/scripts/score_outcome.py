#!/usr/bin/env python3
"""Score the IaC a run wrote, over the union of every .tf under infra/ - the same for both arms.

The eval harness can grade only one file per grader, and real code is spread over many files,
so the `outcome-*` cases only assert that code was written. This reads the kept workspaces of
`claude plugin eval --keep-temp` (one directory per run and arm) and applies the checks below
to the concatenated code. It only reads; nothing in the directories is executed.

    score_outcome.py <case> <workspace> [<workspace> ...] [--label NAME=<workspace>]

A workspace is the kept run directory (it holds home/cwd/infra) or the directory containing
infra/. Checks per case are in CHECKS; a check is (name, weight, pattern, must_match).
"""
import glob
import os
import re
import sys

ANY = r'(?:\s*(?:#[^\n]*)?\n)*'  # nothing: kept for readability of patterns below

CHECKS = {
    'outcome-private-storage': [
        ('public-access-disabled', 2, r'public_network_access(?:_enabled)?\s*=\s*(?:"Disabled"|false)|publicNetworkAccess\W+Disabled', True),
        ('tls-1-2', 1, r'min_tls_version\s*=\s*"TLS1_2"|minimum_tls_version\s*=\s*"TLS1_2"|minimumTlsVersion\W+TLS1_2', True),
        ('no-shared-key', 1, r'shared_access_key_enabled\s*=\s*false|allowSharedKeyAccess\W+false', True),
        ('no-anonymous-blob', 1, r'allow_nested_items_to_be_public\s*=\s*false|allow_blob_public_access\s*=\s*false|allowBlobPublicAccess\W+false', True),
        ('private-endpoint', 2, r'private_endpoints|azurerm_private_endpoint|Microsoft\.Network/privateEndpoints', True),
        ('references-the-subnet', 1, r'snet-privatelink', True),
        ('diagnostics-to-platform-workspace', 1, r'log-platform-prod-we', True),
        ('uses-avm', 1, r'Azure/avm-res-storage-storageaccount', True),
        ('does-not-create-the-vnet', 2, r'resource\s+"azurerm_virtual_network"|avm-res-network-virtualnetwork', False),
        ('does-not-create-a-workspace', 2, r'resource\s+"azurerm_log_analytics_workspace"|avm-res-operationalinsights-workspace', False),
        ('no-invented-address-range', 2, r'\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/\d{1,2}\b', False),
        ('has-tests', 1, None, True),  # a *.tftest.hcl exists
    ],
}


def infra_dir(ws):
    for cand in (os.path.join(ws, 'home', 'cwd', 'infra'), os.path.join(ws, 'infra'), ws):
        if os.path.isdir(cand) and glob.glob(os.path.join(cand, '**', '*.tf'), recursive=True):
            return cand
    return None


def load(ws):
    d = infra_dir(ws)
    if not d:
        return None, '', []
    tf = sorted(glob.glob(os.path.join(d, '**', '*.tf'), recursive=True)
                + glob.glob(os.path.join(d, '**', '*.tfvars'), recursive=True))  # values live in the stage files too
    tests = sorted(glob.glob(os.path.join(d, '**', '*.tftest.hcl'), recursive=True))
    code = '\n'.join(open(f, encoding='utf-8', errors='replace').read() for f in tf)
    return d, code, tests


def score(case, ws):
    d, code, tests = load(ws)
    if d is None:
        return None
    rows = []
    for name, weight, pattern, must in CHECKS[case]:
        if pattern is None:
            ok = bool(tests)
        else:
            ok = bool(re.search(pattern, code, re.I)) == must
        rows.append((name, weight, ok))
    return d, rows


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    case, spaces = argv[1], argv[2:]
    if case not in CHECKS:
        print(f'no checks for case {case!r}; known: {", ".join(CHECKS)}')
        return 2
    results = {}
    for item in spaces:
        label, _, path = item.partition('=') if '=' in item else (os.path.basename(item), '', item)
        res = score(case, path or item)
        results[label] = res
        if res is None:
            print(f'{label}: no .tf files under infra/ - nothing written')
    labels = [l for l, r in results.items() if r]
    if not labels:
        return 1
    names = [n for n, _, _, _ in CHECKS[case]]
    width = max(len(n) for n in names)
    print(f'{"":{width}}  w  ' + '  '.join(f'{l[:14]:14}' for l in labels))
    for i, n in enumerate(names):
        w = CHECKS[case][i][1]
        print(f'{n:{width}}  {w}  ' + '  '.join(f'{"pass" if results[l][1][i][2] else "FAIL":14}' for l in labels))
    print()
    for l in labels:
        rows = results[l][1]
        got = sum(w for _, w, ok in rows if ok)
        tot = sum(w for _, w, _ in rows)
        print(f'{l}: {got}/{tot} weighted, {sum(ok for *_, ok in rows)}/{len(rows)} checks')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))

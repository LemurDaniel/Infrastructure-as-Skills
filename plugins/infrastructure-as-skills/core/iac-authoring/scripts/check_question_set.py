#!/usr/bin/env python3
"""Validates question sets against the question-set format.

Read-only. The repo's check_repo_consistency.py reads the files with regexes
and catches the structural mistakes; this script parses them and checks what
a regex cannot see - what references/question-set-format.md promises:

  1. The envelope: schema_version, scope, title; for a resource set the
     resource type and both naming identifiers plus the abbreviation, the
     Bicep identifier without `Azure::`, the Terraform one with it, and the
     two agreeing.
  2. Groups: unique ids, each with a title and questions, the review-order
     groups (placement, networking, identity, security, data_protection,
     observability) in that relative order.
  3. Questions: unique ids; id, ask, type, why and renders present; a known
     type; `values` for an enum; a default within `values` (enum) or a subset
     of them (list); a default of the type's kind; `ref` on a ref question.
  4. Resolution: `required`, `default`, `from_deployment` and `parameterized`
     are mutually exclusive, and a question carries one of them - a question
     with none has no answer path.
  5. References: `depends_on` names a question in the same set and, for an
     enum, a value it can take; `from_deployment` and `from_context` name a
     question in the deployment set; `confirm_in` names environments the
     deployment set knows; `derived_from` names a customer question in the
     deployment set and maps every one of its values to a value of this
     question's kind (and, for an enum, one of its values).
  6. `audience` is present and is customer, engineer or platform - who answers
     the question; a question without one would reach the customer by accident.
  7. Unknown fields are reported: a misspelt `default` is a question that is
     silently asked every run.
  8. With --platform <file>: the platform profile's keys are deployment-set
     questions with audience platform, enum values are within `values`, and a
     ref value is a name and resource group, not a resource id.

Needs PyYAML (pip install pyyaml). Without it the script says so and exits 2
rather than pretending the files are fine.

Usage:
    python3 check_question_set.py <path>...
    python3 check_question_set.py --platform ./platform.yaml

A path is a questions.yaml, a resource directory, a family directory, the
resources root, or the deployment set. Directories are searched for
questions.yaml and questions/*.yaml. With no path, every set in the plugin.

Exit 0 clean, 1 violations, 2 could not check (no parser, no file).
"""

import argparse
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PLUGIN = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
DEPLOYMENT_SET = os.path.join(HERE, '..', 'questions', 'deployment.yaml')

TYPES = ['enum', 'bool', 'string', 'int', 'list', 'ref']
AUDIENCES = ['customer', 'engineer', 'platform']
REVIEW_ORDER = ['placement', 'networking', 'identity', 'security', 'data_protection', 'observability']
RESOLUTION_FIELDS = ['required', 'default', 'from_deployment', 'parameterized', 'derived_from']
KNOWN_FIELDS = {
    'id', 'ask', 'type', 'values', 'default', 'required', 'parameterized', 'confirm_in',
    'why', 'renders', 'depends_on', 'ref', 'from_deployment', 'forced_when', 'from_context',
    'audience', 'plain', 'derived_from',
}
DERIVED_KEYS = {'question', 'map'}
KNOWN_TOP = {'schema_version', 'scope', 'resource', 'title', 'naming', 'boundaries', 'groups'}

COLORS = {'cyan': '36', 'green': '32', 'red': '31', 'yellow': '33', 'gray': '90'}
USE_COLOR = sys.stdout.isatty() and not os.environ.get('NO_COLOR')


def say(text, color=None):
    if color and USE_COLOR:
        print(f"\033[{COLORS[color]}m{text}\033[0m")
    else:
        print(text)


def ok(text): say(f"[ ok ] {text}", 'green')
def bad(text): say(f"[fail] {text}", 'red')
def warn(text): say(f"[warn] {text}", 'yellow')


def find_sets(paths):
    """Expand files and directories into question-set paths, sorted, unique."""
    found = set()
    for p in paths:
        if os.path.isfile(p):
            found.add(os.path.abspath(p))
            continue
        if not os.path.isdir(p):
            bad(f"no such file or directory: {p}")
            continue
        for d, dirs, files in os.walk(p):
            dirs[:] = [x for x in dirs if x not in ('.git', 'node_modules', '.terraform', 'results')]
            for f in files:
                full = os.path.join(d, f)
                if re.match(r'^questions\.ya?ml$', f) or (
                        os.path.basename(d) == 'questions' and re.search(r'\.ya?ml$', f)):
                    found.add(os.path.abspath(full))
    return sorted(found)


def questions_of(doc):
    """Every question in a parsed set, with its group id."""
    out = []
    for g in (doc.get('groups') or []) if isinstance(doc, dict) else []:
        if not isinstance(g, dict):
            continue
        for q in (g.get('questions') or []):
            if isinstance(q, dict):
                out.append((g.get('id'), q))
    return out


def kind_matches(qtype, value):
    if qtype == 'bool':
        return isinstance(value, bool)
    if qtype == 'int':
        return isinstance(value, int) and not isinstance(value, bool)
    if qtype in ('string', 'ref'):
        return isinstance(value, str)
    if qtype == 'enum':
        return isinstance(value, (str, int, bool))
    if qtype == 'list':
        return isinstance(value, list)
    return True


def check_set(path, doc, deployment, rel):
    """Returns (errors, warnings, question count)."""
    errors, warnings = [], []

    def err(t): errors.append(f"{rel}: {t}")
    def wrn(t): warnings.append(f"{rel}: {t}")

    if not isinstance(doc, dict):
        err('does not parse as a mapping')
        return errors, warnings, 0

    # --- 1. envelope -------------------------------------------------------
    scope = doc.get('scope', 'resource')
    if scope not in ('resource', 'deployment'):
        err(f"scope '{scope}' is not resource or deployment")
    if 'schema_version' not in doc:
        err('schema_version is missing')
    if not doc.get('title'):
        err('title is missing')
    for k in doc:
        if k not in KNOWN_TOP:
            wrn(f"unknown top-level field '{k}'")

    if scope == 'resource':
        if not doc.get('resource'):
            err('resource (the Azure resource type) is missing')
        naming = doc.get('naming')
        if not isinstance(naming, dict):
            err('naming block is missing - both identifiers and the abbreviation are declared here')
        else:
            tf, bc, ab = naming.get('terraform'), naming.get('bicep'), naming.get('abbreviation')
            if not tf:
                err('naming.terraform is missing')
            elif not str(tf).startswith('Azure::'):
                err(f"naming.terraform '{tf}' lacks the Azure:: prefix the naming provider expects")
            if not bc:
                err('naming.bicep is missing')
            elif str(bc).startswith('Azure::'):
                err(f"naming.bicep '{bc}' carries an Azure:: prefix; Bicep spells the type bare")
            if tf and bc and str(tf) != f"Azure::{bc}":
                err(f"naming.terraform '{tf}' and naming.bicep '{bc}' name different types")
            if not ab:
                err('naming.abbreviation is missing - the Bicep render assembles the name from it')
            elif not re.match(r'^[a-z0-9]{1,8}$', str(ab)):
                err(f"naming.abbreviation '{ab}' is not short lowercase alphanumeric")
            if bc and doc.get('resource') and str(bc) != str(doc['resource']):
                wrn(f"naming.bicep '{bc}' differs from resource '{doc['resource']}'")
    else:
        for k in ('resource', 'naming'):
            if k in doc:
                err(f"a deployment set names no resource; drop '{k}'")

    # --- 2. groups ---------------------------------------------------------
    groups = doc.get('groups')
    if not isinstance(groups, list) or not groups:
        err('groups is missing or empty')
        return errors, warnings, 0
    gids = []
    for g in groups:
        if not isinstance(g, dict):
            err('a group is not a mapping')
            continue
        gid = g.get('id')
        if not gid:
            err('a group has no id')
        gids.append(gid)
        if not g.get('title'):
            err(f"group '{gid}' has no title")
        if not isinstance(g.get('questions'), list) or not g['questions']:
            err(f"group '{gid}' has no questions")
    dupes = sorted({x for x in gids if gids.count(x) > 1}, key=str)
    if dupes:
        err(f"duplicate group id(s): {', '.join(map(str, dupes))}")
    if scope == 'resource':
        seen = [g for g in gids if g in REVIEW_ORDER]
        if seen != sorted(seen, key=REVIEW_ORDER.index):
            wrn(f"review-order groups out of order: {' -> '.join(seen)}; the format fixes "
                f"{' -> '.join(REVIEW_ORDER)} so a reviewer does not relearn the layout per resource")

    # --- 3-7. questions ----------------------------------------------------
    qs = questions_of(doc)
    ids = [q.get('id') for _, q in qs]
    dupes = sorted({x for x in ids if ids.count(x) > 1}, key=str)
    if dupes:
        err(f"duplicate question id(s): {', '.join(map(str, dupes))}. Ids are an interface - pattern pre-answers and specs name them.")
    by_id = {q.get('id'): q for _, q in qs}

    dep_ids = {q.get('id'): q for _, q in questions_of(deployment)} if deployment else {}
    dep_context = {q.get('id') for g, q in questions_of(deployment) if g == 'context'} if deployment else set()
    env_values = []
    if deployment and 'environment' in dep_ids:
        env_values = dep_ids['environment'].get('values') or []

    for gid, q in qs:
        qid = q.get('id') or '<no id>'
        where = f"{gid}.{qid}"

        for k in q:
            if k not in KNOWN_FIELDS:
                err(f"{where}: unknown field '{k}'" + (" - did you mean 'default'?" if k.lower().startswith('def') else ''))

        for k in ('id', 'ask', 'type', 'why', 'renders'):
            if not q.get(k):
                err(f"{where}: '{k}' is missing")
        if q.get('why') and len(str(q['why']).strip()) < 40:
            wrn(f"{where}: why is one line; the format wants what breaks or what it costs if the other value is chosen")

        qtype = q.get('type')
        if qtype and qtype not in TYPES:
            err(f"{where}: type '{qtype}' is not one of {', '.join(TYPES)}")

        values = q.get('values')
        if qtype == 'enum':
            if not isinstance(values, list) or not values:
                err(f"{where}: an enum needs a non-empty values list")
        elif values is not None and qtype != 'list':
            wrn(f"{where}: values on a {qtype} question is not read; only enum and list use it")
        if values is not None and isinstance(values, list):
            vd = sorted({str(v) for v in values if values.count(v) > 1})
            if vd:
                err(f"{where}: duplicate value(s): {', '.join(vd)}")

        if qtype == 'ref' and not q.get('ref'):
            err(f"{where}: a ref question names what it points at (ref: subnet, log_analytics_workspace, ...)")
        if q.get('ref') and qtype not in ('ref', 'list'):
            wrn(f"{where}: ref on a {qtype} question; the format uses it on ref and list")

        # --- 4. resolution
        # `default: false` is a default; `required: false` is not a requirement.
        present = [f for f in RESOLUTION_FIELDS if q.get(f) is not None
                   and not (f in ('required', 'parameterized') and q[f] is False)]
        if len(present) > 1:
            err(f"{where}: {' and '.join(present)} together; they are mutually exclusive")
        if not present and not q.get('from_context'):
            err(f"{where}: no required, default, from_deployment or parameterized - the question has no answer path")
        if 'required' in q and not isinstance(q['required'], bool):
            err(f"{where}: required must be true or false")
        if 'parameterized' in q and not isinstance(q['parameterized'], bool):
            err(f"{where}: parameterized must be true or false")
        if q.get('parameterized') and scope != 'deployment':
            wrn(f"{where}: parameterized outside the deployment set; context values live there")

        if 'default' in q and q['default'] is not None and qtype:
            d = q['default']
            if not kind_matches(qtype, d):
                err(f"{where}: default {d!r} is not a {qtype}")
            if qtype == 'enum' and isinstance(values, list) and d not in values:
                err(f"{where}: default '{d}' is not in values {values}")
            if qtype == 'list' and isinstance(values, list) and isinstance(d, list):
                off = [x for x in d if x not in values]
                if off:
                    err(f"{where}: default item(s) not in values: {off}")

        # --- 5. references
        dep = q.get('depends_on')
        if dep is not None:
            if not isinstance(dep, dict) or 'question' not in dep:
                err(f"{where}: depends_on must be {{ question: <id>, equals: <value> }} or not_equals")
            else:
                target = dep['question']
                cond = [k for k in ('equals', 'not_equals') if k in dep]
                if len(cond) != 1:
                    err(f"{where}: depends_on needs exactly one of equals / not_equals")
                extra = set(dep) - {'question', 'equals', 'not_equals'}
                if extra:
                    err(f"{where}: depends_on has unknown key(s) {sorted(extra)}")
                if target == qid:
                    err(f"{where}: depends_on itself")
                elif target not in by_id:
                    err(f"{where}: depends_on '{target}', which is not a question in this set")
                elif cond:
                    tq = by_id[target]
                    tv = tq.get('values')
                    v = dep[cond[0]]
                    if tq.get('type') == 'enum' and isinstance(tv, list) and v not in tv:
                        err(f"{where}: depends_on {target} {cond[0]} '{v}', which {target} cannot take (values {tv})")
                    if tq.get('type') == 'bool' and not isinstance(v, bool):
                        err(f"{where}: depends_on {target} {cond[0]} {v!r}, but {target} is a bool")

        fd = q.get('from_deployment')
        if fd is not None:
            if scope == 'deployment':
                err(f"{where}: from_deployment inside the deployment set")
            elif deployment is None:
                wrn(f"{where}: from_deployment '{fd}' not checked - the deployment set did not load")
            elif fd not in dep_ids:
                err(f"{where}: from_deployment '{fd}', which the deployment set does not have")
            else:
                tq = dep_ids[fd]
                if qtype == 'enum' and tq.get('type') == 'enum' and isinstance(values, list):
                    tv = tq.get('values') or []
                    if set(map(str, tv)) == set(map(str, values)):
                        pass  # same vocabulary, inherited as-is
                    # different vocabularies are mapped in `why`; nothing to check mechanically

        dv = q.get('derived_from')
        if dv is not None:
            if scope == 'deployment':
                err(f"{where}: derived_from inside the deployment set")
            elif not isinstance(dv, dict) or set(dv) != DERIVED_KEYS:
                err(f"{where}: derived_from must be {{ question: <deployment id>, map: {{ <answer>: <value> }} }}")
            elif deployment is None:
                wrn(f"{where}: derived_from '{dv.get('question')}' not checked - the deployment set did not load")
            elif dv['question'] not in dep_ids:
                err(f"{where}: derived_from '{dv['question']}', which the deployment set does not have")
            else:
                tq = dep_ids[dv['question']]
                if tq.get('audience') != 'customer':
                    err(f"{where}: derived_from '{dv['question']}', whose audience is {tq.get('audience')} - a derivation answers a customer question; otherwise use from_deployment")
                tv = tq.get('values') if tq.get('type') == 'enum' else None
                m = dv['map']
                if not isinstance(m, dict) or not m:
                    err(f"{where}: derived_from.map must be a non-empty mapping")
                else:
                    if tv is not None:
                        missing = [v for v in tv if v not in m]
                        extra = [k for k in m if k not in tv]
                        if missing:
                            err(f"{where}: derived_from.map has no entry for {missing} - every answer to {dv['question']} must derive a value")
                        if extra:
                            err(f"{where}: derived_from.map names answer(s) {extra} that {dv['question']} cannot take")
                    for k, v in m.items():
                        if qtype and not kind_matches(qtype, v):
                            err(f"{where}: derived_from.map[{k!r}] = {v!r} is not a {qtype}")
                        if qtype == 'enum' and isinstance(values, list) and v not in values:
                            err(f"{where}: derived_from.map[{k!r}] = '{v}' is not in values {values}")

        if q.get('from_context'):
            if scope == 'deployment':
                err(f"{where}: from_context inside the deployment set")
            elif deployment is not None and qid not in dep_context:
                err(f"{where}: from_context, but the deployment set's context group has no '{qid}'")

        ci = q.get('confirm_in')
        if ci is not None:
            if not isinstance(ci, list) or not ci:
                err(f"{where}: confirm_in must be a non-empty list of environments")
            elif env_values:
                off = [e for e in ci if e not in env_values]
                if off:
                    err(f"{where}: confirm_in names environment(s) the deployment set does not know: {off}")

        # --- 6. audience
        aud = q.get('audience')
        if aud is None:
            err(f"{where}: audience is missing (customer | engineer | platform) - who answers it?")
        elif aud not in AUDIENCES:
            err(f"{where}: audience '{aud}' is not one of {', '.join(AUDIENCES)}")

    return errors, warnings, len(qs)


PLATFORM_TOP = {'schema_version', 'platform'}


def check_platform(doc, deployment, rel):
    """A platform.yaml: keys are deployment-set questions with audience platform."""
    errors = []

    def err(t): errors.append(f"{rel}: {t}")

    if not isinstance(doc, dict):
        err('does not parse as a mapping')
        return errors
    if deployment is None:
        err('the deployment set did not load, so the keys cannot be checked')
        return errors
    if 'schema_version' not in doc:
        err('schema_version is missing')
    meta = doc.get('platform')
    if not isinstance(meta, dict) or not meta.get('id'):
        err("platform.id is missing - a wrong value needs an owner, and the spec names the profile")
    dep = {q.get('id'): q for _, q in questions_of(deployment)}
    for k, v in doc.items():
        if k in PLATFORM_TOP:
            continue
        q = dep.get(k)
        if q is None:
            err(f"'{k}' is not a deployment-set question")
            continue
        if q.get('audience') != 'platform':
            err(f"'{k}' has audience {q.get('audience')}, not platform - it is not the platform's to fix")
            continue
        t, values = q.get('type'), q.get('values')
        if t == 'enum' and isinstance(values, list) and v not in values:
            err(f"'{k}': '{v}' is not in {values}")
        elif t == 'ref':
            if isinstance(v, str) and v.startswith('/subscriptions/'):
                err(f"'{k}' is a resource id; the deployment set takes a name and resource group, so no subscription is pinned")
            elif isinstance(v, dict) and 'name' not in v and 'subscription_id' not in v:
                err(f"'{k}' names neither a name nor a subscription_id")
        elif t in ('string', 'int', 'bool', 'list') and not kind_matches(t, v):
            err(f"'{k}': {v!r} is not a {t}")
    return errors


def main():
    ap = argparse.ArgumentParser(description='Validate question sets against the question-set format.')
    ap.add_argument('paths', nargs='*', help='questions.yaml files or directories holding them; default: the whole plugin')
    ap.add_argument('--platform', metavar='FILE',
                    help='a platform.yaml to check against the deployment set instead of question sets')
    args = ap.parse_args()

    try:
        import yaml
    except ImportError:
        bad('no YAML parser available')
        say('       Install one and re-run:', 'gray')
        say('         pip install pyyaml', 'gray')
        return 2

    def load(p):
        with open(p, encoding='utf-8') as f:
            return yaml.safe_load(f)

    deployment = None
    dep_path = os.path.abspath(DEPLOYMENT_SET)
    if os.path.isfile(dep_path):
        try:
            deployment = load(dep_path)
        except yaml.YAMLError:
            deployment = None

    if args.platform:
        if not os.path.isfile(args.platform):
            bad(f"no such file: {args.platform}")
            return 2
        say(f"Platform profile check - {os.path.abspath(args.platform)}", 'cyan')
        print('-' * 70)
        try:
            doc = load(args.platform)
        except yaml.YAMLError as e:
            bad(f"YAML does not parse: {e}")
            return 1
        errors = check_platform(doc, deployment, os.path.basename(args.platform))
        if errors:
            bad(f"{len(errors)} violation(s)")
            for e in errors:
                say(f"         {e}", 'gray')
            return 1
        n = len([k for k in doc if k not in PLATFORM_TOP])
        say(f"{n} platform value(s), every one a deployment-set question the platform owns.", 'green')
        return 0

    paths = args.paths or [PLUGIN]
    sets = find_sets(paths)
    if not sets:
        bad('no question sets found')
        return 2

    say(f"Question-set check - {len(sets)} file(s)", 'cyan')
    print('-' * 70)

    errors, warnings, total = [], [], 0
    for p in sets:
        rel = os.path.relpath(p, PLUGIN) if p.startswith(PLUGIN) else p
        try:
            doc = load(p)
        except yaml.YAMLError as e:
            errors.append(f"{rel}: YAML does not parse: {e}")
            bad(rel)
            continue
        dep = deployment if os.path.abspath(p) != dep_path else None
        e, w, n = check_set(p, doc, dep, rel)
        total += n
        errors.extend(e)
        warnings.extend(w)
        scope = doc.get('scope', 'resource') if isinstance(doc, dict) else '?'
        (bad if e else ok)(f"{rel} - {n} question(s), scope {scope}" + (f", {len(e)} problem(s)" if e else ''))

    print('-' * 70)
    for w in warnings:
        warn(w)
    if errors:
        print()
        bad(f"{len(errors)} violation(s) across {len(sets)} file(s)")
        for e in errors:
            say(f"         {e}", 'gray')
        return 1
    print()
    say(f"{total} question(s) in {len(sets)} set(s) match the format." + (f" {len(warnings)} warning(s)." if warnings else ''), 'green')
    return 0


if __name__ == '__main__':
    sys.exit(main())

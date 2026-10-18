#!/usr/bin/env python3
"""Draws an infra-spec.yaml as infra-diagram.drawio, with a computed layout.

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

Needs PyYAML (pip install pyyaml). Without it the script exits 2.

Usage:
    python3 new_diagram.py ./infra-spec.yaml --language de [--out ./infra-diagram.drawio]

Exit 0 written, 1 layout check failed or spec unreadable, 2 could not run.
"""

import argparse
import math
import os
import re
import sys
from xml.sax.saxutils import escape as _xml_escape

COLORS = {'green': '32', 'red': '31', 'yellow': '33'}
USE_COLOR = sys.stdout.isatty() and not os.environ.get('NO_COLOR')


def say(text, color=None):
    if color and USE_COLOR:
        print(f"\033[{COLORS[color]}m{text}\033[0m")
    else:
        print(text)


def esc(s):
    """XML-escape like .NET's SecurityElement.Escape: & < > " and '."""
    return _xml_escape('' if s is None else str(s), {'"': '&quot;', "'": '&apos;'})


def num(v):
    """Geometry values: integral floats print without a decimal part."""
    if isinstance(v, float) and v.is_integer():
        return str(int(v))
    return str(v)


def s(v):
    """PowerShell-style string interpolation: None is the empty string."""
    return '' if v is None else str(v)


LABELS = {
    'en': {
        'internet': 'Internet', 'noPublic': 'no public access', 'existing': 'existing - not created',
        'decisions': 'Decisions', 'open': 'Open', 'assumed': 'Assumed', 'exposure': 'Exposure',
        'network': 'Network', 'mandates': 'Mandates', 'dns': 'Private DNS', 'diag': 'Diagnostics',
        'forces': 'forces', 'peSubnet': 'private endpoints', 'owner': 'owner',
    },
    'de': {
        'internet': 'Internet', 'noPublic': 'kein öffentlicher Zugriff', 'existing': 'vorhanden - wird nicht erstellt',
        'decisions': 'Entscheidungen', 'open': 'Offen', 'assumed': 'Angenommen', 'exposure': 'Erreichbarkeit',
        'network': 'Netzwerk', 'mandates': 'Vorgaben', 'dns': 'Private DNS', 'diag': 'Diagnose',
        'forces': 'erzwingt', 'peSubnet': 'Private Endpoints', 'owner': 'zuständig',
    },
}

# Every resource with a question set has a row. Paths verified against draw.io's
# azure2 library - a wrong path exports as a broken-image placeholder, silently.
ICONS = {
    'subscription': 'img/lib/azure2/general/Subscriptions.svg',
    'resource-group': 'img/lib/azure2/general/Resource_Groups.svg',
    'storage-account': 'img/lib/azure2/storage/Storage_Accounts.svg',
    'virtual-network': 'img/lib/azure2/networking/Virtual_Networks.svg',
    'private-endpoint': 'img/lib/azure2/networking/Private_Endpoint.svg',
    'private-dns-zone': 'img/lib/azure2/networking/DNS_Zones.svg',
    'log-analytics-workspace': 'img/lib/azure2/analytics/Log_Analytics_Workspaces.svg',
    'key-vault': 'img/lib/azure2/security/Key_Vaults.svg',
    'app-service': 'img/lib/azure2/app_services/App_Services.svg',
}
TYPE_NAMES = {
    'storage-account': 'Storage Account', 'virtual-network': 'Virtual Network',
    'log-analytics-workspace': 'Log Analytics Workspace', 'key-vault': 'Key Vault',
    'app-service': 'App Service',
}

# A slot holds an icon and up to four label lines below it. The label is given
# the slot's width via labelWidth - without it draw.io wraps the label to the
# 48px image and breaks after every word.
SLOT_W, SLOT_H, ICON = 190, 130, 48
LABEL_W = SLOT_W - 10
HEAD, PAD, LANE_GAP, TRACK = 44, 20, 120, 14

CONTAINER_STYLE = 'rounded=1;arcSize=2;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#0078D4;verticalAlign=top;align=left;spacingLeft=36;spacingTop=4;fontStyle=1;container=1;collapsible=0;'
EXISTING_STYLE = 'dashed=1;strokeColor=#999999;fontColor=#777777;'
SUBNET_STYLE = 'rounded=1;arcSize=4;whiteSpace=wrap;html=1;fillColor=#F3F9FD;strokeColor=#7FBAEA;verticalAlign=top;align=left;spacingLeft=10;spacingTop=2;container=1;collapsible=0;'
EDGE_BASE = 'edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;endArrow=block;endFill=1;'


def get_at(m, keys):
    cur = m
    for k in keys:
        if not isinstance(cur, dict) or k not in cur:
            return None
        cur = cur[k]
    return cur


STAGES = {'development', 'test', 'qa', 'uat', 'integration', 'staging', 'preproduction',
          'production', 'sandbox', 'demo', 'hotfix'}


# A per-stage value is a map keyed by stage. The page draws one picture, so it shows
# the value every stage shares, else production's, else the first stage's - printing
# the map itself leaks Python's dict syntax into the labels.
def collapse_stages(v):
    if isinstance(v, dict) and v and set(v) <= STAGES:
        vals = list(v.values())
        if all(x == vals[0] for x in vals):
            return vals[0]
        return v.get('production', vals[0])
    return v


# A decision is either { value, source } or a bare value.
def get_value(node):
    if isinstance(node, dict) and 'value' in node:
        return collapse_stages(node['value'])
    return collapse_stages(node)


def get_decision(m, keys):
    return get_value(get_at(m, keys))


# A referenced resource is recorded as "name / resource-group", or as a map with
# name and resource_group_name. The name goes on the shape; the group goes to
# the panel, where text has room. Putting both on an icon label overflows its
# fixed slot.
def split_ref(value):
    if value is None:
        return {'name': None, 'rg': None}
    if isinstance(value, dict):
        return {'name': value.get('name'), 'rg': value.get('resource_group_name') or value.get('resource_group')}
    parts = re.split(r'\s*/\s*', str(value), maxsplit=1)
    return {'name': parts[0], 'rg': parts[1] if len(parts) > 1 else None}


def as_list(v):
    if v is None:
        return []
    if isinstance(v, list):
        return v
    return [v]


def format_label(title, sub, note):
    label = f"<b>{esc(title)}</b>"
    if sub:
        label += f"<br><font style='font-size:10px'>{esc(sub)}</font>"
    if note:
        label += f"<br><font style='font-size:10px'><i>{esc(note)}</i></font>"
    return label


def icon_style(img, flagged, existing):
    style = f"image;aspect=fixed;html=1;points=[];align=center;verticalLabelPosition=bottom;verticalAlign=top;whiteSpace=wrap;labelBackgroundColor=none;labelWidth={LABEL_W};image={img};"
    if existing:
        style += 'opacity=60;fontColor=#777777;'
    if flagged:
        style += 'fontColor=#D13438;'
    return style


def plain_len(html):
    return len(re.sub(r'<[^>]+>', '', html))


def main():
    ap = argparse.ArgumentParser(description='Draw an infra-spec.yaml as a draw.io diagram.')
    ap.add_argument('path', help='the infra-spec.yaml to draw')
    ap.add_argument('--out', help='the .drawio to write (default: infra-diagram.drawio next to the spec)')
    ap.add_argument('--language', choices=['de', 'en'], default='en',
                    help='language of the fixed labels and the decisions panel; Azure names, types, ranges and roles are never translated')
    args = ap.parse_args()

    if not os.path.isfile(args.path):
        say(f"[skip] {args.path} not found.", 'yellow')
        return 2
    full = os.path.abspath(args.path)
    out = args.out or os.path.join(os.path.dirname(full), 'infra-diagram.drawio')

    # --- Parse -------------------------------------------------------------
    try:
        import yaml
    except ImportError:
        say('[skip] no YAML parser - pip install pyyaml', 'yellow')
        return 2
    try:
        with open(full, encoding='utf-8') as f:
            spec = yaml.safe_load(f) or {}
    except yaml.YAMLError as e:
        say(f"[fail] YAML does not parse: {e}", 'red')
        return 1

    T = LABELS[args.language]

    # --- Read the spec -----------------------------------------------------
    ctx = get_at(spec, ['context']) or {}
    dep = get_at(spec, ['deployment'])
    resources = get_at(spec, ['resources']) or {}

    exposure = s(get_decision(dep, ['network_exposure']))
    net_ownership = s(get_decision(dep, ['network_ownership']))
    obs_ownership = s(get_decision(dep, ['observability_ownership']))
    dns_ownership = s(get_decision(dep, ['private_dns_ownership']))
    is_private = exposure in ('private', 'private_with_exceptions')

    res_keys = sorted(resources.keys())
    has_vnet_res = 'virtual-network' in res_keys
    has_law_res = 'log-analytics-workspace' in res_keys
    draw_vnet = has_vnet_res or net_ownership in ('create', 'reference')
    vnet_existing = (not has_vnet_res) and net_ownership == 'reference'

    # Resources drawn in the middle column: everything that is not the network or the workspace.
    middle = [k for k in res_keys if k not in ('virtual-network', 'log-analytics-workspace')]

    # Which resources get a private endpoint: an explicit subnet on the resource, or
    # a private posture. The workspace is reached through AMPLS, not drawn here.
    with_pe = [k for k in middle
               if is_private or get_decision(resources[k], ['networking', 'private_endpoint_subnet']) is not None]
    without_pe = [k for k in middle if k not in with_pe]

    pe_subnet_name = split_ref(get_decision(dep, ['private_endpoint_subnet']))['name']
    pe_subnet_prefix = get_decision(dep, ['private_endpoint_subnet_prefix'])
    if not pe_subnet_name:
        # Under network_ownership: create the deployment set holds only the prefix; the
        # generated subnet's name is on the resources that use it.
        for k in with_pe:
            pe_subnet_name = split_ref(get_decision(resources[k], ['networking', 'private_endpoint_subnet']))['name']
            if pe_subnet_name:
                break
    if not pe_subnet_name:
        pe_subnet_name = 'snet-' + T['peSubnet'].lower().replace(' ', '')

    other_subnets = []
    for sn in as_list(get_decision(resources.get('virtual-network'), ['addressing', 'subnets'])):
        if sn is None:
            continue
        if isinstance(sn, dict):
            name = sn.get('name') if sn.get('name') is not None else sn.get('id')
            prefix = sn.get('prefix')
            if prefix is None:
                prefix = sn.get('address_prefix')
            if prefix is None:
                prefix = ', '.join(s(p) for p in as_list(sn.get('address_prefixes')))
        else:
            name, prefix = str(sn), ''
        if name and name != pe_subnet_name:
            other_subnets.append({'name': name, 'prefix': prefix})

    roles = [r for r in as_list(get_decision(spec, ['wiring', 'role_assignments'])) if r]
    zones = [z for z in as_list(get_decision(spec, ['wiring', 'private_dns_zones'])) if z]
    diag_ref = split_ref(get_decision(dep, ['diagnostics_destination']))
    diag_target = diag_ref['name']
    vnet_ref = split_ref(get_decision(dep, ['existing_vnet']))
    draw_law = has_law_res or bool(diag_target)

    # assumed values anywhere in the spec, by dotted path
    assumed = []

    def find_assumed(node, path):
        if isinstance(node, dict):
            if 'source' in node and s(node['source']) == 'assumed':
                assumed.append(path)
            for k in node:
                find_assumed(node[k], f"{path}.{k}" if path else str(k))

    find_assumed(spec, '')
    open_items = [o for o in as_list(get_at(spec, ['open'])) if o]

    # A resource is flagged when an open or assumed entry points into it.
    def flagged(key):
        prefix = f"resources.{key}."
        if any(a.startswith(prefix) for a in assumed):
            return True
        return any(s(o.get('key') if isinstance(o, dict) else None).startswith(prefix) for o in open_items)

    # --- Layout ------------------------------------------------------------
    # All geometry is absolute while laying out; the emitter converts children to
    # coordinates relative to their container, which is what draw.io expects.
    cells = []

    def add_cell(c):
        cells.append(c)
        return c

    # One icon in a fixed slot: centred horizontally, label below inside the slot.
    def add_icon(cid, parent, slot_x, slot_y, kind, label, is_flagged=False, existing=False):
        img = ICONS.get(kind)
        if img:
            style = icon_style(img, is_flagged, existing)
            x, y, w, h = slot_x + (SLOT_W - ICON) / 2, slot_y + 8, ICON, ICON
        else:
            say(f"[warn] no icon for '{kind}' - drawn as a box", 'yellow')
            # Same height and centre as an icon, so edges into it stay straight.
            style = 'rounded=1;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#605E5C;'
            if is_flagged:
                style += 'fontColor=#D13438;'
            x, y, w, h = slot_x + 20, slot_y + 8, SLOT_W - 40, ICON
        add_cell({'id': cid, 'parent': parent, 'x': x, 'y': y, 'w': w, 'h': h, 'style': style, 'value': label,
                  'slot': {'x': slot_x, 'y': slot_y, 'w': SLOT_W, 'h': SLOT_H}, 'labelBelow': bool(img)})

    internet_w = 160 if exposure == 'public' else 0
    sub_x, sub_y = 20 + internet_w, 20
    rg_x, rg_y = sub_x + PAD, sub_y + HEAD
    lane_y = rg_y + HEAD + 10
    lane_x = rg_x + PAD

    # Network lane
    row_y = {}   # resource key -> absolute row y, shared by its endpoint and itself
    net_right = lane_x - LANE_GAP
    vn_x = vn_y = vn_w = vn_h = 0
    pe_sn = None
    other_boxes = []
    if draw_vnet:
        vn_x, vn_y = lane_x, lane_y
        sn_x = vn_x + PAD
        cursor = vn_y + HEAD

        pe_rows = max(len(with_pe), 1)
        pe_sn = {'x': sn_x, 'y': cursor, 'w': SLOT_W + 2 * PAD, 'h': 34 + pe_rows * SLOT_H + 10}
        for i, k in enumerate(with_pe):
            row_y[k] = pe_sn['y'] + 34 + i * SLOT_H
        cursor += pe_sn['h'] + PAD

        for sn in other_subnets:
            other_boxes.append({'name': sn['name'], 'prefix': sn['prefix'], 'x': sn_x, 'y': cursor, 'w': pe_sn['w'], 'h': 44})
            cursor += 44 + 10
        vn_w = pe_sn['w'] + 2 * PAD
        vn_h = cursor - vn_y + PAD - (10 if other_boxes else 0)
        net_right = vn_x + vn_w
    else:
        for i, k in enumerate(with_pe):
            row_y[k] = lane_y + i * SLOT_H

    # Resource lane: endpoint-backed resources on their endpoint's row, the rest after.
    res_x = net_right + LANE_GAP
    nxt = lane_y
    if with_pe:
        nxt = max(row_y[k] for k in with_pe) + SLOT_H
    for k in without_pe:
        row_y[k] = nxt
        nxt += SLOT_H
    res_bottom = (max(row_y[k] for k in middle) + SLOT_H) if middle else lane_y
    # Right of the resource column run vertical tracks: one per role assignment,
    # then one shared by every diagnostics edge. Separate tracks are what keeps the
    # lines from running on top of each other.
    # The gap before the first track holds the role labels, which sit on each
    # edge's last segment into its target.
    role_track_x = res_x + SLOT_W + (50 if roles else 0)
    diag_track_x = role_track_x + (len(roles) + 1) * TRACK
    res_right = (diag_track_x + TRACK) if middle else (res_x - LANE_GAP)

    # Observability lane: workspace on top, then the DNS zones.
    obs_x = res_right + LANE_GAP
    obs_y = min(row_y[k] for k in middle) if middle else lane_y
    obs_count = (1 if draw_law else 0) + len(zones)
    obs_right = (obs_x + SLOT_W) if obs_count else res_right
    obs_bottom = obs_y + obs_count * SLOT_H

    content_bottom = max(res_bottom, obs_bottom, lane_y + SLOT_H)
    if draw_vnet:
        content_bottom = max(content_bottom, vn_y + vn_h)
    rg_w = obs_right + PAD - rg_x
    rg_h = content_bottom + PAD - rg_y + (24 if is_private else 0)
    sub_w = rg_w + 2 * PAD
    sub_h = rg_h + HEAD + PAD

    # --- Cells -------------------------------------------------------------
    sub_label = format_label('Subscription', s(get_value(ctx.get('subscription_id'))), '')
    add_cell({'id': 'sub', 'parent': '1', 'x': sub_x, 'y': sub_y, 'w': sub_w, 'h': sub_h, 'style': CONTAINER_STYLE, 'value': sub_label})
    add_cell({'id': 'sub-icon', 'parent': 'sub', 'x': sub_x + 6, 'y': sub_y + 6, 'w': 24, 'h': 24,
              'style': f"image;aspect=fixed;html=1;image={ICONS['subscription']};", 'value': ''})

    loc, env_ = s(get_value(ctx.get('location'))), s(get_value(ctx.get('environment')))
    rg_name = get_value(ctx.get('resource_group_name'))
    rg_label = format_label(s(rg_name if rg_name is not None else 'resource group'), ' · '.join(p for p in (loc, env_) if p != ''), '')
    add_cell({'id': 'rg', 'parent': 'sub', 'x': rg_x, 'y': rg_y, 'w': rg_w, 'h': rg_h, 'style': CONTAINER_STYLE, 'value': rg_label})
    add_cell({'id': 'rg-icon', 'parent': 'rg', 'x': rg_x + 6, 'y': rg_y + 6, 'w': 24, 'h': 24,
              'style': f"image;aspect=fixed;html=1;image={ICONS['resource-group']};", 'value': ''})

    if is_private:
        add_cell({'id': 'rg-private', 'parent': 'rg', 'x': rg_x + PAD, 'y': rg_y + rg_h - 26, 'w': rg_w - 2 * PAD, 'h': 20,
                  'style': 'text;html=1;align=left;verticalAlign=middle;fontColor=#107C10;fontStyle=2;', 'value': f"&#128274; {T['noPublic']}"})

    vn_sub = ''
    if draw_vnet:
        vn_name = vnet_ref['name'] if (vnet_existing and vnet_ref['name']) else 'Virtual Network'
        addr = get_decision(dep, ['address_space'])
        if addr is None:
            addr = get_decision(resources.get('virtual-network'), ['addressing', 'address_space'])
        vn_sub = s(addr)
        vn_note = T['existing'] if vnet_existing else ''
        style = CONTAINER_STYLE + (EXISTING_STYLE if vnet_existing else '')
        add_cell({'id': 'vnet', 'parent': 'rg', 'x': vn_x, 'y': vn_y, 'w': vn_w, 'h': vn_h, 'style': style, 'value': format_label(vn_name, vn_sub, vn_note)})
        add_cell({'id': 'vnet-icon', 'parent': 'vnet', 'x': vn_x + 6, 'y': vn_y + 6, 'w': 24, 'h': 24,
                  'style': f"image;aspect=fixed;html=1;image={ICONS['virtual-network']};", 'value': ''})

        pe_label = f"<b>{esc(pe_subnet_name)}</b>" + (f"  <font style='font-size:10px'>{pe_subnet_prefix}</font>" if pe_subnet_prefix else '')
        add_cell({'id': 'snet-pe', 'parent': 'vnet', 'x': pe_sn['x'], 'y': pe_sn['y'], 'w': pe_sn['w'], 'h': pe_sn['h'],
                  'style': SUBNET_STYLE + (EXISTING_STYLE if vnet_existing else ''), 'value': pe_label})
        for k in with_pe:
            add_icon(f"pe-{k}", 'snet-pe', pe_sn['x'] + PAD, row_y[k], 'private-endpoint', format_label('Private Endpoint', k, ''))
        for j, b in enumerate(other_boxes):
            lbl = f"<b>{esc(b['name'])}</b>" + (f"  <font style='font-size:10px'>{b['prefix']}</font>" if b['prefix'] else '')
            add_cell({'id': f"snet-{j}", 'parent': 'vnet', 'x': b['x'], 'y': b['y'], 'w': b['w'], 'h': b['h'], 'style': SUBNET_STYLE, 'value': lbl})

    for k in middle:
        add_icon(f"res-{k}", 'rg', res_x, row_y[k], k, format_label(TYPE_NAMES.get(k, k), k, ''), flagged(k))

    oy = obs_y
    if draw_law:
        law_existing = (not has_law_res) and obs_ownership != 'create'
        law_name = s(diag_target) if diag_target else 'log-analytics-workspace'
        add_icon('law', 'rg', obs_x, oy, 'log-analytics-workspace',
                 format_label('Log Analytics', law_name, T['existing'] if law_existing else ''),
                 flagged('log-analytics-workspace'), law_existing)
        oy += SLOT_H
    for z, zone in enumerate(zones):
        z_existing = dns_ownership != 'deployment'
        add_icon(f"dns-{z}", 'rg', obs_x, oy, 'private-dns-zone', format_label(s(zone), '', T['existing'] if z_existing else ''), False, z_existing)
        oy += SLOT_H

    if exposure == 'public' and middle:
        iy = min(row_y[k] for k in middle)
        add_cell({'id': 'internet', 'parent': '1', 'x': 30, 'y': iy + 8 + ICON / 2 - 30, 'w': 100, 'h': 60,
                  'style': 'ellipse;shape=cloud;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#605E5C;', 'value': T['internet']})

    # Decisions panel, right of the subscription.
    lines = []
    lines.append(f"<b>{T['decisions']}</b>")
    if exposure:
        lines.append(f"{T['exposure']}: <b>{esc(exposure)}</b>")
    if net_ownership:
        lines.append(f"{T['network']}: {esc(net_ownership)}" + (f", {esc(vn_sub)}" if vn_sub else ''))
    mand = [m for m in as_list(get_decision(dep, ['mandates'])) if m]
    if mand:
        lines.append(f"{T['mandates']}: {esc(', '.join(s(m) for m in mand))}")
    if dns_ownership:
        lines.append(f"{T['dns']}: {esc(dns_ownership)}")
    if diag_target:
        lines.append(f"{T['diag']}: {esc(diag_target)}" + (f" ({esc(diag_ref['rg'])})" if diag_ref['rg'] else ''))
    if vnet_existing and vnet_ref['rg']:
        lines.append(f"VNet: {esc(vnet_ref['name'])} ({esc(vnet_ref['rg'])})")
    # forced chains: deployment answers carrying `forces`
    if isinstance(dep, dict):
        for k in dep:
            for entry in [e for e in as_list(get_at(dep, [k, 'forces'])) if e]:
                if isinstance(entry, dict):
                    txt = ', '.join(f"{ek} = {ev}" for ek, ev in entry.items())
                else:
                    txt = s(entry)
                lines.append(f"<font color='#8A6100'>{esc(k)}: {esc(get_decision(dep, [k]))} → {T['forces']} {esc(txt)}</font>")
    if open_items:
        lines.append('')
        lines.append(f"<b><font color='#D13438'>{T['open']}</font></b>")
        for o in open_items:
            o = o if isinstance(o, dict) else {}
            owner = f" <i>({T['owner']}: {esc(o['owner'])})</i>" if o.get('owner') else ''
            q = o.get('question') if o.get('question') is not None else o.get('key')
            lines.append(f"<font color='#D13438'>• {esc(q)}</font>{owner}")
    if assumed:
        lines.append('')
        lines.append(f"<b><font color='#D13438'>{T['assumed']}</font></b>")
        for a in assumed:
            lines.append(f"<font color='#D13438'>• {esc(a)}</font>")
    panel_w = 340
    # Rough wrap estimate: ~48 characters per line at 12px in 340px.
    panel_lines = sum(max(1, math.ceil(plain_len(line) / 48)) for line in lines)
    panel_h = max(80, panel_lines * 18 + 24)
    add_cell({'id': 'panel', 'parent': '1', 'x': sub_x + sub_w + 40, 'y': sub_y, 'w': panel_w, 'h': panel_h,
              'style': 'rounded=1;arcSize=3;whiteSpace=wrap;html=1;align=left;verticalAlign=top;spacing=12;fillColor=#F3F2F1;strokeColor=#C8C6C4;',
              'value': '<br>'.join(lines)})

    # --- Edges -------------------------------------------------------------
    by_id = {c['id']: c for c in cells}

    def anchor_y(cid, fy):
        return by_id[cid]['y'] + by_id[cid]['h'] * fy

    edges = []
    for k in with_pe:
        if draw_vnet:
            edges.append({'id': f"e-pe-{k}", 'source': f"pe-{k}", 'target': f"res-{k}",
                          'style': EDGE_BASE + 'exitX=1;exitY=0.5;entryX=0;entryY=0.5;strokeColor=#0078D4;', 'value': ''})
    r = 0
    for ra in roles:
        ra = ra if isinstance(ra, dict) else {}
        frm, to = f"res-{s(ra.get('from'))}", f"res-{s(ra.get('to'))}"
        if frm not in by_id or to not in by_id:
            say(f"[warn] role assignment {s(ra.get('from'))} -> {s(ra.get('to'))}: endpoint not drawn", 'yellow')
            continue
        tx = role_track_x + (r + 1) * TRACK
        # The role name sits on the segment into the target: one per target row, so
        # two roles from the same principal do not stack on its shared stub.
        # Wrapped at ~18 characters to fit the gap.
        wrapped, line = [], ''
        for word in s(ra.get('role')).split(' '):
            if line and (len(line) + 1 + len(word)) > 18:
                wrapped.append(line)
                line = word
            else:
                line = f"{line} {word}" if line else word
        if line:
            wrapped.append(line)
        edges.append({'id': f"e-role-{r}", 'source': frm, 'target': to, 'value': '<br>'.join(esc(w) for w in wrapped), 'labelAt': 0.7,
                      'style': EDGE_BASE + 'exitX=1;exitY=0.3;entryX=1;entryY=0.3;strokeColor=#5C2D91;fontColor=#5C2D91;fontSize=10;labelBackgroundColor=#FFFFFF;',
                      'points': [{'x': tx, 'y': anchor_y(frm, 0.3)}, {'x': tx, 'y': anchor_y(to, 0.3)}]})
        r += 1
    if draw_law:
        law_y = anchor_y('law', 0.5)
        for k in middle:
            edges.append({'id': f"e-diag-{k}", 'source': f"res-{k}", 'target': 'law', 'value': '',
                          'style': EDGE_BASE + 'exitX=1;exitY=0.7;entryX=0;entryY=0.5;dashed=1;strokeColor=#8A8886;endArrow=open;',
                          'points': [{'x': diag_track_x, 'y': anchor_y(f"res-{k}", 0.7)}, {'x': diag_track_x, 'y': law_y}]})
    if exposure == 'public':
        for k in middle:
            edges.append({'id': f"e-inet-{k}", 'source': 'internet', 'target': f"res-{k}", 'value': '',
                          'style': EDGE_BASE + 'exitX=1;exitY=0.5;entryX=0;entryY=0.5;strokeColor=#D83B01;'})

    # --- Overlap check -----------------------------------------------------
    # Siblings must not overlap. An icon is checked by its slot (icon + label), not
    # by its 48px image, since the label is what collides first.
    def box(c):
        return c['slot'] if c.get('slot') else {'x': c['x'], 'y': c['y'], 'w': c['w'], 'h': c['h']}

    problems = []
    by_parent = {}
    for c in cells:
        if c['id'].endswith('-icon') or c['id'] == 'rg-private':
            continue
        by_parent.setdefault(c['parent'], []).append(c)
    for group in by_parent.values():
        for a in range(len(group)):
            for b in range(a + 1, len(group)):
                p, q = box(group[a]), box(group[b])
                if p['x'] < q['x'] + q['w'] and q['x'] < p['x'] + p['w'] and p['y'] < q['y'] + q['h'] and q['y'] < p['y'] + p['h']:
                    problems.append(f"{group[a]['id']} overlaps {group[b]['id']}")
    # A label below an icon must end inside its slot. Estimated: ~26 characters
    # per line at the slot's label width, 16px per line.
    for c in cells:
        if not c.get('labelBelow'):
            continue
        line_count = sum(max(1, math.ceil(plain_len(part) / 26)) for part in c['value'].split('<br>'))
        if c['y'] + c['h'] + 4 + line_count * 16 > c['slot']['y'] + c['slot']['h']:
            problems.append(f"{c['id']}: label of {line_count} lines does not fit its slot")
    # Children must fit inside their container.
    for c in cells:
        if c['parent'] == '1':
            continue
        p, b = by_id[c['parent']], box(c)
        if b['x'] < p['x'] or b['y'] < p['y'] or b['x'] + b['w'] > p['x'] + p['w'] or b['y'] + b['h'] > p['y'] + p['h']:
            problems.append(f"{c['id']} leaves its container {c['parent']}")
    if problems:
        for p in problems:
            say(f"[fail] {p}", 'red')
        return 1

    # --- Emit --------------------------------------------------------------
    diagram_name = get_at(spec, ['spec', 'id'])
    o = []
    o.append('<mxfile host="infrastructure-as-skills-azure">')
    o.append(f'  <diagram id="infra" name="{esc(diagram_name if diagram_name is not None else "infra")}">')
    o.append('    <mxGraphModel grid="1" gridSize="10" page="0" math="0" shadow="0">')
    o.append('      <root>')
    o.append('        <mxCell id="0"/>')
    o.append('        <mxCell id="1" parent="0"/>')
    for c in cells:
        px = py = 0
        if c['parent'] != '1':
            px, py = by_id[c['parent']]['x'], by_id[c['parent']]['y']
        o.append(f'        <mxCell id="{c["id"]}" value="{esc(c["value"])}" style="{esc(c["style"])}" vertex="1" parent="{c["parent"]}">')
        o.append(f'          <mxGeometry x="{num(c["x"] - px)}" y="{num(c["y"] - py)}" width="{num(c["w"])}" height="{num(c["h"])}" as="geometry"/>')
        o.append('        </mxCell>')
    for e in edges:
        o.append(f'        <mxCell id="{e["id"]}" value="{esc(e["value"])}" style="{esc(e["style"])}" edge="1" parent="1" source="{e["source"]}" target="{e["target"]}">')
        if e.get('points'):
            # Waypoints are absolute, since every edge's parent is the root layer.
            pts = ''.join(f'<mxPoint x="{num(p["x"])}" y="{num(p["y"])}"/>' for p in e['points'])
            label_pos = f' x="{num(e["labelAt"])}"' if e.get('labelAt') else ''
            # A label rides above its segment rather than on it, so it never covers the arrowhead.
            offset = '<mxPoint y="-16" as="offset"/>' if e.get('labelAt') else ''
            o.append(f'          <mxGeometry relative="1"{label_pos} as="geometry"><Array as="points">{pts}</Array>{offset}</mxGeometry>')
        else:
            o.append('          <mxGeometry relative="1" as="geometry"/>')
        o.append('        </mxCell>')
    o.append('      </root>')
    o.append('    </mxGraphModel>')
    o.append('  </diagram>')
    o.append('</mxfile>')

    with open(out, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(o) + '\n')
    say(f"[ ok ] {out} - {len(cells)} shapes, {len(edges)} edges, no overlaps", 'green')
    return 0


if __name__ == '__main__':
    sys.exit(main())

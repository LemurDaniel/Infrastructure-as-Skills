---
name: iac-diagram
description: Draws an infra-spec.yaml as an editable draw.io diagram, exported as infra-diagram.drawio.png — what gets built, how it connects, what stays open. Read after a spec is written, or when asked for an architecture picture of one.
---

# Drawing the spec

The spec is written for reviewers and backends. The person who asked for the
infrastructure usually reads neither YAML nor HCL, and still has to say whether this is
what they meant. This skill gives them a picture of the same decisions.

```
infra-spec.yaml  ──new_diagram──>  infra-diagram.drawio  ──export_diagram──>  infra-diagram.drawio.png
```

It draws **from the spec, never from rendered code**. That is what lets the diagram come
before rendering — iac-authoring offers it once the spec is written, and asks about code
only after: the customer signs off on the picture while changing a decision is
still one line in the spec, not a regenerated module. It also keeps the diagram identical
for Terraform and Bicep, as the spec is.

## Run it

```sh
python3 <plugin>/core/iac-diagram/scripts/new_diagram.py    ./infra-spec.yaml --language de
python3 <plugin>/core/iac-diagram/scripts/export_diagram.py ./infra-diagram.drawio
```

`--language` is the user's language, `de` or `en`. It covers the fixed labels and the
decisions panel; Azure names, types, ranges and role names stay as Azure spells them,
since those are what the customer will find in the portal.

**Do not write the draw.io XML by hand.** The layout is computed: every icon has a fixed
slot, containers are sized from their contents, each edge type has its own track, and the
script fails if any two shapes or labels overlap. A hand-placed diagram gets every one of
those wrong in a way that only shows in the picture — labels that wrap after every word
because they inherit the 48px icon width, a label running into the icon below, two role
names stacked on the same line. If the generated layout is wrong, fix the script.

| File | What it is |
|---|---|
| `infra-diagram.drawio` | The source. Plain XML, stable ids from spec keys, so a regeneration diffs readably |
| `infra-diagram.drawio.png` | The deliverable. A PNG with the diagram embedded — it opens in a document, a chat or an email like any image, and opens in draw.io as the editable diagram |

Exit codes, both scripts: `0` written, `1` failed, `2` could not run.

- `new_diagram.py` exit 1 with `overlaps` or `does not fit` is a layout bug in the script, not
  something to patch in the output.
- `export_diagram.py` exit 2 means draw.io desktop is not installed. Say so, deliver the
  `.drawio` file, and do not substitute a different renderer — a PNG without the embedded
  diagram is a picture the customer cannot correct.

**Regeneration overwrites both.** Manual edits in draw.io are lost on the next run. A change
the customer makes in the picture is a change to a decision, and it goes back into the spec.

## What it shows

One page, the decisions a customer can judge. Not forty attributes.

```
 Internet │ subscription > resource group > [ network │ resources │ observability ] │ decisions
```

| Spec | Drawn as |
|---|---|
| `context` | Nested containers: subscription → resource group, region and environment in the group's label |
| `deployment.address_space`, `virtual-network` subnets | A virtual network container, the private-endpoint subnet and every other subnet inside it with their ranges |
| `resources:` | One Azure icon per resource, labelled with its type and spec key |
| Private endpoint | In its subnet, on the same row as the resource it fronts — a straight edge |
| `deployment.network_exposure` | `public`: an *Internet* actor with an edge to each resource. `private`: endpoints for every resource, and the group marked as having no public access |
| `wiring.role_assignments` | A purple line on the target's label (`← principal: role`), not an edge - several roles from one principal made a bundle of lines nobody could follow |
| A resource type with no icon | A box with the type's name, marked as having no question set; the script warns |
| Diagnostics | Dashed edges on a shared track into the workspace |
| `network_ownership: reference`, a referenced workspace, platform-owned DNS zones | Grey and faded, labelled as existing and not created |
| `open:` entries, `assumed` values | The affected resource in red, and listed in the panel |

Plus a **decisions panel** on the right: exposure, network, mandates, DNS and diagnostics
ownership, every forced chain (`key_protection: hsm → forces key-vault.sku = premium`), and
the open items with who has to answer them. A forced cost is the decision a customer most
needs to see and the one an icon cannot show.

What it leaves out: SKUs nobody asked about, TLS floors, soft-delete days, every `default`
from the guardrail baseline. They are in the spec and in the Phase 4 report; on the
picture they are noise that hides the topology.

**Existing is not created.** Drawing a referenced VNet in the same style as a new one tells
the customer this run builds it. The grey styling is the boundary this run stops at.

## Check before handing it over

Export a preview without the embedded diagram and look at it — the overlap check covers
geometry, not taste:

```powershell
python3 <plugin>/core/iac-diagram/scripts/export_diagram.py ./infra-diagram.drawio --out <scratch>/preview.png --no-embed
```

Then check it against the spec: every resource in `resources:` drawn exactly once, every
`open:` entry in the panel, nothing drawn that the spec does not contain. A `[warn] no
icon` from `new_diagram.py` means a resource was drawn as a plain box — say so.

## Icons

`ICONS` in [new_diagram.py](scripts/new_diagram.py) maps each resource key to a path in
draw.io's built-in `azure2` library. Every resource with a question set needs a row there.

Check a new path in the preview before adding it: a wrong path does not fail, it exports
as a broken-image placeholder. `azure2` has no subnet shape, which is why subnets are
containers.

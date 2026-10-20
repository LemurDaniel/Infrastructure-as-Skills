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
python3 <plugin>/core/iac-diagram/scripts/verify_diagram.py  ./infra-spec.yaml ./infra-diagram.drawio --language de
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

Exit codes, all scripts: `0` ok, `1` failed, `2` could not run.

- `new_diagram.py` exit 1 with `overlaps` or `does not fit` is a layout bug in the script, not
  something to patch in the output.
- `export_diagram.py` exit 2 means draw.io desktop is not installed. Say so, deliver the
  `.drawio` file, and do not substitute a different renderer — a PNG without the embedded
  diagram is a picture the customer cannot correct.
- `export_diagram.py` repairs and checks the PNG after an embedded export. The draw.io
  desktop CLI writes a bad zTXt CRC and no IEND chunk with `--embed-diagram`, every time:
  browsers still show it, strict decoders (and Claude's image reader) reject it. Never
  call the draw.io CLI directly, and never hand over a PNG `drawio_png.py check` calls BAD.
  `--scale` (default 2) and `--border` (default 20) are options.

**Regeneration overwrites both.** Manual edits in draw.io are lost on the next run. A change
the customer makes in the picture is a change to a decision, and it goes back into the spec.

To see what the customer changed, take the XML out of their PNG and diff it against a fresh
generation. The ids are stable, so the diff shows the cells they moved, renamed or added:

```sh
python3 <plugin>/core/iac-diagram/scripts/drawio_png.py extract ./theirs.drawio.png <scratch>/theirs.drawio
python3 <plugin>/core/iac-diagram/scripts/new_diagram.py ./infra-spec.yaml --out <scratch>/fresh.drawio
diff <scratch>/fresh.drawio <scratch>/theirs.drawio
```

Each difference is a question for the spec ("you renamed the subnet - is the range still
right?"), not a patch for the diagram.

## Audience

Decide it before drawing. The default is the **customer**: the person who asked for the
infrastructure and has to say whether this is what they meant. Their picture has no repo
names, file paths, variable names, module versions or Terraform internals, and no process
commentary. It is phrased for their tenant, not for how it is built.

An **engineer** reviewing the render also wants the AVM module and version behind each
resource and the spec keys. That is a different picture from a different question; say so
and offer it, rather than putting module versions on the customer's.

## What it shows

One page, the decisions a customer can judge. Not forty attributes.

```
 external zone │ resource group > [ virtual network: subnets with their compute │ Azure PaaS ] │ monitoring, name resolution │ decisions
```

The picture answers one question: **who can reach what.** It is drawn in zones, and the
lines are access, not plumbing.

| Spec | Drawn as |
|---|---|
| `context` | The resource group as the outermost container, region and environment in its label; no subscription frame (it changes per environment and adds only a layer); title and one-line subtitle (exposure, keyless) above |
| `virtual-network` subnets, `deployment.address_space` | A virtual network zone with its subnets and ranges. A subnet that hosts compute carries its delegation (`delegated to Microsoft.Web/serverFarms`) |
| Compute (`app-service`, `function-app`, `container-app`, `virtual-machine`, …) | An icon inside the subnet named by its `networking.integration_subnet` decision, else the first integration-like subnet |
| Other `resources:` (storage, vault, database, bus, registry, …) | An icon in the *Azure PaaS* zone below the network, titled *public access disabled* when every one is. A PaaS service is not in the VNet; its endpoint is |
| Private endpoints | **One** bundled icon in the endpoint subnet (`9× app-service, function-app +7`), not one per resource |
| `wiring.access` | The lines: `{ from, to, label }`. `from` and `to` are resource keys or actors - `internet`, `users`, `external:<name>` - which sit in the *Internet and external services* zone. A line to a PaaS service runs on a shared track and splits on a bus lane, like a tree |
| `wiring.role_assignments` | A line as well, if `wiring.access` has none for the pair, and `← principal: role` in purple on the target's label |
| `deployment.network_exposure: public` | An *Internet* actor with an orange line to each compute resource (or PaaS service if there is no compute) |
| Blue and orange lines | Blue: private path, no public route. Orange: from or over the internet, or to a target whose public access is not disabled |
| `wiring.purposes` | What a resource is for, under its type (`Storage Account · Product images`); without one, the spec key |
| `wiring.optional` | The listed resources marked *optional* and faded; the legend says so |
| A resource type with no icon | A box with the type's name, marked as having no question set; the script warns |
| Diagnostics | **Not** a line per resource: a *Monitoring* zone with the workspace and the note *Diagnostic settings of all resources* |
| Private DNS zones | One bundled icon in a *Name resolution* zone (`8× privatelink.*`) |
| Referenced things (`network_ownership: reference`, a central workspace, platform DNS) | Grey and dashed, outside the resource group, labelled as existing and not created |
| `open:` entries, `assumed` values | The affected resource in red, and listed in the panel |

A legend at the bottom lists only what the picture uses.

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

1. `verify_diagram.py` checks the file against the spec: every resource in `resources:`
   drawn exactly once, nothing drawn that the spec does not contain, every `open:` entry in
   the picture, every `wiring.optional` resource faded. With `--language de` it also fails
   on transliterated umlauts (`ueber`, `oeffentlich`) in any label. The network and the
   workspace are drawn even when the spec only references them, and application insights
   next to the workspace; those are not extras.
2. Export a preview and look at it — the overlap check covers geometry, not taste:

```powershell
python3 <plugin>/core/iac-diagram/scripts/export_diagram.py ./infra-diagram.drawio --out <scratch>/preview.png --no-embed
```

3. A `[warn] no icon` from `new_diagram.py` means a resource was drawn as a plain box —
   say so.
4. `drawio_png.py check ./infra-diagram.drawio.png` is `OK`, not `BAD`.

`drawio_png.py labels <file>` lists every label of a `.drawio` or a `.drawio.png` as text,
to read or grep without opening draw.io.

## Icons

`ICONS` in [new_diagram.py](scripts/new_diagram.py) maps each resource key to a path in
draw.io's built-in `azure2` library. Every resource with a question set needs a row there.

Find a path with `drawio_png.py icons <word> [<word>]` (e.g. `icons azure2 key`), never from
memory. A wrong path does not fail, it exports as a broken-image placeholder.
`run_png_tests.py` checks every path in `ICONS` against draw.io's bundled library, and
`drawio_png.py check` warns about unknown paths in a PNG. `azure2` has no subnet shape,
which is why subnets are containers.

## Tests

```sh
python3 <plugin>/core/iac-diagram/tests/run_diagram_tests.py   # fixture specs in, assertions on the drawing out
python3 <plugin>/core/iac-diagram/tests/run_png_tests.py       # PNG repair, extract/embed, verify_diagram, icon table
```

Run both after changing anything under `scripts/`.

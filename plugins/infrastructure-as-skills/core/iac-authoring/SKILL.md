---
name: iac-authoring
description: The interview protocol behind every skill here — how a question set becomes infra-spec.yaml, which questions get asked versus silently defaulted, and what the spec records. Read before authoring any Azure resource or pattern, when extending a question set, or when asked why a default was chosen.
---

# Authoring infrastructure from a question set

Each resource family under `resources/` holds one directory per resource, and its
`questions.yaml` carries the decisions that resource forces, grouped by concern. This file is the
protocol for turning a question set into a spec, and the spec into code. Follow it rather
than improvising — the value of the plugin is that two runs of the same skill ask the same
things and record them the same way.

Three units, kept apart on purpose: the [azure-resources](../azure-resources/SKILL.md)
skill is the **triggering** unit, the family the **routing** unit, the question set the
**knowledge** unit. They are separate because the skill listing has a shared character
budget, and a description that overflows it is dropped silently — the skill stays
installed and stops matching. A skill per resource would spend the budget at once; a skill
per family spent it by the sixth family.

## The pipeline

```
question set  ──interview──>  infra-spec.yaml  ──render──>  Terraform / Bicep  ──validate──>  explained plan
                 [here]             │         [iac-rendering]
                                    └──draw──>  infra-diagram.drawio.png
                                                [iac-diagram]
```

The spec in the middle is the load-bearing part. It is the handover interface, not a
by-product: a backend renders *from* it, and the same spec can go to a different backend —
including `Infrastructure-by-Skill` for API-driven execution — which is what makes the two
tracks comparable at all. Never generate code directly from the interview.

## Before anything — find an existing spec

Search the repository for `**/infra-spec.yaml` first. If one exists, this run **extends**
it rather than starting over: its decisions are carried, Phase 0 asks what should be added
or changed, and only the delta is asked and reported. If none exists, the spec this run
writes goes into the repository's IaC root, or `infra/` when there is none, and is
committed with the code — it is what the next run extends. The rules for both, and for
several roots, are in [references/spec.md](references/spec.md#where-it-lives).

## Phase 0 — Ask what is being built, in the user's own words

The interview opens with one open question, not with the question set. Let the user
describe what they are building, and let that description answer as much as it can.
Only what it leaves open is asked afterwards.

The reason is the order of cost. A paragraph of prose is cheap to write and typically
settles the environment, the region, what the thing is for, who reaches it and from where,
and whether a mandate applies — half the deployment set, before a single structured
question. Starting with the question set instead asks those things one field at a time,
and asks some that the user would have answered in passing.

**Skip it when the request already is that description.** "Storage für die Rechnungsablage
der Buchhaltung, Prod in West Europe, nur aus dem Firmennetz, BSI C5" needs no opening
question. A bare resource name — "ich brauch ein storage account für terraform" — is not a
description; it names the resource and nothing about the system around it.

Ask in plain text, not through `AskUserQuestion`: the point is free prose, and options
would turn it back into the structured interview it precedes. Give the user a short list
of what is worth mentioning, so the description lands on the questions that matter:

```
Beschreib kurz, was du aufbauen willst. Hilfreich ist alles davon, nichts davon ist Pflicht:
  - Wofür ist es da, und für welche Umgebung (dev / test / prod)?
  - Region, Subscription, Resource Group — falls schon festgelegt
  - Wer oder was greift zu, und von wo (Internet, Firmennetz, nur andere Azure-Dienste)?
  - Gibt es Vorgaben (BSI C5, ISO 27001, interne Richtlinien)?
  - Was existiert schon (VNet, Log Analytics Workspace, DNS) und soll genutzt werden?
```

Then map the answer onto the deployment set and every routed question set. Everything it
settles is recorded with `source: stated` and is not asked again. Three rules for the
mapping:

- **A value is stated only if the user said it.** "Nur intern" settles
  `network_exposure: private`; it does not settle an address range. An inferred value that
  the text does not carry belongs to the normal resolution order, not to `stated`.
- **A contradiction is asked, not resolved.** "Öffentlich erreichbar" next to "nur aus dem
  Firmennetz" is one question in Phase 3, quoting both halves.
- **The description may add resources.** "…mit Logs nach Log Analytics" routes a second
  question set through [azure-resources](../azure-resources/SKILL.md) — the same request,
  one interview, one spec.

What remains open goes into Phase 3's batches. The description does not replace them; it
shrinks them, and usually to the `required` questions nobody mentions unprompted.

## Phase 1 — Establish the target and the layout

Terraform or Bicep. Do not ask if the repository answers it:

- `*.tf` or `.terraform.lock.hcl` present → Terraform
- `*.bicep` or `bicepconfig.json` present → Bicep
- both, or neither → then ask, once

The same reading settles how the code is split, which the spec records under
`composition.granularity`:

- An existing `modules/` directory → match what is there, per module and per file
- An existing `infra-spec.yaml` → its `composition` is `carried`; do not re-decide it
- A flat repository, or a single resource → `single`
- Otherwise → `per-concern`

Deciding this before the interview matters because it is the one thing both backends must
agree on. If the split is settled per renderer, the same spec produces one Terraform root
and six Bicep files, and comparing the two outputs stops meaning anything. See
[references/spec.md](references/spec.md#modularity).

## Phase 2 — Resolve the deployment set, then every resource question

[`questions/deployment.yaml`](questions/deployment.yaml) is resolved **before** any
resource question set. It holds what is one decision per system rather than one per
resource, in two halves:

- **The context** — environment, region, workload, subscription, resource group. All
  `required`, because nothing can be guessed and everything downstream reads them. A
  resource question marked `from_context: true` points here; without this group that field
  pointed at nothing, and a run could reach the renderer with no region and therefore no
  name.
- **The deployment decisions** — network exposure, local auth, who owns the virtual
  network and the workspace, mandates and what they force, DNS ownership, retention and
  the ingestion cap.

Resolve it once and every resource inherits it. A resource question carrying
`from_deployment: <id>` is answered from there and never asked again — eight resources in
one run must not produce eight separate exposure answers, and a system is not private
because seven of them are.

For each question, the answer then comes from the first source that has one:

| # | Source | `source` recorded as |
|---|---|---|
| 1 | What the user said — the request and the Phase 0 description | `stated`, or `overridden` where it changes a carried value |
| 2 | The existing `infra-spec.yaml` | `carried` |
| 3 | A pattern skill's pre-answers | `pattern` |
| 4 | The deployment set's answer, for a `from_deployment` question | `deployment` |
| 5 | The question's `default` | `default` |

A carried value outranks a pattern and a default on purpose: it was decided, and quite
possibly deployed. A re-run that let a pattern or a changed guardrail flip it would turn
"add a key vault" into a silent change to the storage account. Only the user changes a
carried value. Consequences are the exception — `deployment` and `forced` values are
re-derived from what they follow, not carried.

A question with `required: true` has no default and no safe guess. It is the only kind you
must ask.

**A forced value is pre-answered, not asked.** `key_protection: hsm` requires a Premium Key
Vault; `network_exposure: private` requires the private-endpoint subnet. Apply the
consequence, record it with the question that forced it, and say so in Phase 4 rather than
putting a question whose answer is already determined to the user.

Defaults are not invented per resource — they come from
[references/guardrails.md](references/guardrails.md), which is also where their reasoning
lives. Read it before choosing any default or justifying one.

## Phase 3 — Ask, in at most two batches

Only what Phase 0's description left open reaches this phase. A question the user already
answered in prose and is asked again tells them the description was not read.

**Fold Phase 1's question into the first batch** when the repository did not answer it.
Target and layout are two more questions, not a separate exchange — a round trip per
phase is the serial interrogation this protocol exists to avoid.

**The deployment batch first, on its own.** Its answers decide which resource questions
survive at all — `network_exposure` removes the firewall questions, `local_auth` settles
the key switch on every resource — so mixing the two batches asks things that the first
batch would have answered. It also keeps a missing prerequisite where it belongs: that no
workspace and no address range exist yet is a deployment problem, and discovering it
halfway through a storage interview means the interview was wasted.

**Then the resource batch.** Collect every question that survived and put them in a single
exchange. Where
the host offers `AskUserQuestion`, use it — grouped options with the trade-off in the
description beat prose.

A serial interrogation ("and now, the TLS version?") is the one failure mode that makes
people abandon a tool like this, and it is entirely avoidable: the question set is known up
front, so there is no reason to discover questions one at a time.

If more than about six questions survive, you are asking things that should have defaults.
Say so and propose the defaults instead.

**Never offer an invented value as an option.** Grouped options work for an `enum`, where
the values come from the question set. They are wrong for a `ref`, an address range, a
subscription id, a workspace name — anything only the user's environment knows. Offering
`log-we-prod-platform-01` as a choice does not help someone decide; it invites them to pick
a plausible-looking identifier that does not exist, and a wrong ref surfaces at apply time.

For those, ask whether the value is already assigned, and let the answer come as text:

```
Steht ein Adressraum für das neue VNet fest?
  - Ja, ich gebe ihn an            -> the user types the CIDR
  - Nein, noch keiner zugewiesen   -> name it as an open decision, do not pick one
```

An unassigned address range is a blocker to say out loud, not a gap to fill with
`10.0.0.0/16`. The same holds for a workspace that does not exist yet: that is a
boundary — something this run does not create — and the honest answer is to record it as
missing rather than to reference a name nobody has.

**Ask in the user's language; keep the artefacts in English.** The question sets are
written in English, but a question put to someone who wrote their request in German is
translated — including the trade-off in the options, which is the part that earns the
question. What stays English regardless: `infra-spec.yaml`, its `why` entries, code
comments, variable names and commit messages. They are the interface other backends,
reviewers and tools read, and a spec that is half German is a spec nobody can diff. Where
the user wants the reasoning in their language too, that is their call to make — ask once
rather than deciding it for them.

A question may carry `confirm_in: [production]`. Its default still applies, but in that
environment you surface it for confirmation rather than applying it silently — these are
the values whose blast radius makes a silent default inappropriate.

## Phase 4 — Report what was defaulted, before generating

Show a compact account. Not forty rows — group it:

```
Deployment-wide:
  exposure        private - every resource gets a private endpoint, no public surface
  network         own vnet, 10.42.0.0/16
  mandates        BSI C5 -> HSM key protection -> Key Vault Premium
  diagnostics     log-we-prod-platform-01

Defaulted (guardrail baseline):
  Security        TLS 1.2 floor, shared-key auth off, infrastructure encryption on
  Data protection blob soft-delete 7d, container soft-delete 7d, versioning on
  Observability   diagnostics -> Log Analytics, categories: audit + allLogs

Asked:
  environment     production
  location        westeurope
  replication     ZRS
```

The deployment block comes first because it is what the rest hangs off, and a forced value
is shown with what forced it — `HSM -> Premium` is a cost consequence someone may want to
argue with, and they can only do that if they see the chain.

This is the step that keeps the plugin honest. Someone who disagrees with a default needs
to see it to disagree with it, and the ones they never look at cost one glance.

## Phase 5 — Write the spec, then ask twice before rendering

Write `infra-spec.yaml` into the user's repository first — the IaC root, or `infra/` —
and validate it with `Test-Spec.ps1`. Doing that before any code is not bookkeeping: it
forces the decisions to be expressible in the backend-neutral vocabulary, and a decision
that will not fit is usually one that absorbed a backend's spelling.

Then stop and ask. The spec is a finished artefact on its own, and the two steps after it
are the user's to start — each one produces files in their repository.

**First: a diagram?** Ask whether to draw the spec with
[iac-diagram](../iac-diagram/SKILL.md). Recommend it when someone other than the person in
the conversation has to sign off, or when the spec holds more than one resource; skip the
recommendation for a single resource the user clearly understands.

```
Die Spec liegt in infra/infra-spec.yaml. Soll ich daraus ein Diagramm erstellen?
  - Ja (empfohlen)  -> infra-diagram.drawio.png, zum Prüfen oder Weitergeben
  - Nein            -> weiter zur Prüfung der Spec
```

**Second: does it match, and should the code be generated?** Show what the user is
confirming — the diagram if there is one, otherwise the Phase 4 summary — and ask whether
it meets the requirements:

```
Passt das so zu euren Anforderungen?
  - Ja, Terraform-Code erzeugen  -> render into the same directory
  - Etwas ändern                 -> the user says what; change the spec, redraw, ask again
  - Noch nicht                   -> stop here; the spec stays and the next run extends it
```

The order is the point. An objection to the picture is a one-line change to the spec now,
and a regenerated module later. "Etwas ändern" therefore loops back to the spec, never
into the code: change the decision there, as `overridden` where it replaces an answer,
regenerate the diagram if one exists, and ask the second question again.

Never offer code generation as already decided. If the spec still holds `open:` entries or
`assumed` values, say so in the question — the code will then `plan` but not `apply` —
rather than letting "Ja" read as "ready to deploy".

A spec extended by a later run asks the same two questions; the diagram and the code are
regenerated from the whole spec, so the diff shows what the extension moved.

- Spec schema and the `source` field: [references/spec.md](references/spec.md)
- Drawing it: [iac-diagram](../iac-diagram/SKILL.md)
- Rendering it, for either target: [iac-rendering](../iac-rendering/SKILL.md)

## Phase 6 — Validate and explain

Generated code is not done when it is syntactically valid: `fmt` → `validate` →
`plan` / `what-if` → explain what will actually happen and what is risky about it. The
commands per target are at the end of each idiom file in
[iac-rendering](../iac-rendering/SKILL.md).

Do not skip the explanation on the grounds that the plan output is right there. A plan is a
list of attribute diffs; what a reviewer needs is which of those diffs are
service-affecting and which are noise, and that is a judgement the plan cannot make.

## Composition: how a pattern drives a resource

A pattern skill does not re-ask a resource's questions. It supplies a pre-answer block
keyed by resource, entering resolution at precedence 2:

```yaml
pre_answers:
  storage-account:
    public_network_access: disabled
    shared_access_key_enabled: false
    replication: ZRS
  key-vault:
    rbac_authorization: true
```

Two rules make this work:

- **A pattern may pre-answer, never contradict the user.** If the user asked for something
  the pattern pre-answers differently, the user wins — and you say what the pattern
  expected and what the departure implies for the rest of the system.
- **The wiring belongs to the pattern.** Private endpoints, DNS zone links, role
  assignments between the parts, diagnostic routing: no single resource question set can own a
  relationship, so the pattern renders it. This is the genuinely hard part and the main
  reason pattern skills exist.

A pattern may also fix the module split, since it is the only layer that knows which parts
get reused separately. It does that by supplying `composition.modules` entries, recorded
with `source: pattern` like any other pre-answer:

```yaml
composition:
  granularity: per-resource
  modules:
    - id: storage
      contains: [storage-account]
      outputs: [id, principal_id]
    - id: app
      contains: [app-service]
      needs: [storage]
```

The wiring between them stays in `wiring:` and renders into the root, not into a module —
a module that reaches into another module's resources is the failure this split exists to
prevent.

## Adding a resource

A resource goes into a family under `resources/` — `storage`, `network`, `observability`
today, `compute`, `data`, `security` planned. Families are not skills; the single
[azure-resources](../azure-resources/SKILL.md) skill routes into all of them. Inside the
family:

1. Create `<resource>/` in the family and write `<resource>/questions.yaml`. Copy an existing one and keep the group order:
   placement, networking, identity, security, data_protection, observability. The order is
   the review order, and a reviewer reading three resources should not relearn the layout.
2. Fill `why` and `renders` for every question. `why` is what a reviewer reads; `renders`
   names the attribute it drives, which is what lets a review map code back to a decision.
3. Take defaults from [references/guardrails.md](references/guardrails.md) rather than from the
   Azure portal. They differ often, and the portal default is not a baseline worth
   inheriting.
4. Mark `required: true` only where no safe default exists. Every extra required question
   is a tax on every future run.
5. Write `<resource>/notes.md` for what the question set cannot express:
   decisions fixed at creation, dependency order, the pitfalls worth naming out loud.
6. Write `<resource>/terraform.md` and `<resource>/bicep.md` — the
   rendering, not the decisions. Anything true for both belongs in the shared references
   instead.
7. Add a row to the family's `routing.md`, so the resource is reachable, and its icon to the
   `$Icons` table of [iac-diagram](../iac-diagram/SKILL.md#icons), so it is drawable.
8. If people would ask for it with a term the
   [azure-resources](../azure-resources/SKILL.md) description does not carry, add the term
   there — that description is the only trigger the resource has.
9. Validate: `pwsh -NoProfile -File scripts/Test-QuestionSet.ps1 <family-dir>`

A genuinely new family gets a directory under `resources/` with a `routing.md`, and a row in
the azure-resources table. **Not** a skill directory and **not** a `plugin.json` entry:
`resources/` is deliberately undeclared, so nothing in it costs listing budget, and a
family that became a skill again would reintroduce the per-family budget cost that
overflowed at the sixth family.

## Reference files

Read as needed, not up front:

| File | When |
|---|---|
| [references/spec.md](references/spec.md) | Writing or reading `infra-spec.yaml` |
| [references/question-set-format.md](references/question-set-format.md) | Authoring or extending a `questions.yaml` |
| [references/guardrails.md](references/guardrails.md) | Choosing or justifying any default, or weighing an exception |
| [iac-diagram](../iac-diagram/SKILL.md) | Drawing the spec as `infra-diagram.drawio.png` for the customer |
| [iac-rendering](../iac-rendering/SKILL.md) | Turning the spec into Terraform or Bicep — naming, layout, idiom |

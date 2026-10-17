# Progress

The handoff between sessions. Read it at the start of one, rewrite it at the end of one —
the goal rarely changes, the rest does. Keep it tight: what is here is what the next
session starts from, and what is not here it re-derives.

## Goal

A Claude Code plugin that authors Azure infrastructure as Terraform or Bicep from an
interview, consistently: the same request produces the same decisions, every decision is
recorded with where it came from, and a backend renders from that record — onto Azure
Verified Modules first, authored resources second.

## Decisions, and why

- **Question sets, not modules or templates.** The hard part of a resource is its
  decisions, not its syntax. Generic generation gets the syntax right and the decisions
  wrong.
- **Spec in the middle.** `infra-spec.yaml` is the handover; code is rendered from it. It
  makes two backends comparable and regeneration a diff.
- **AVM first, authored second.** A resource with an `Available` Azure Verified Module
  renders as a call to it, every decision an explicit input; a type without one renders
  authored and the spec says so (`implementation: authored`, `source: forced`). The modules
  already implement what the first authored render got wrong — the diagnostic setting
  that collects no blob logs, the endpoint named after the index — with one interface in
  both targets. `deployment.module_source` records it once; `module_telemetry` beside it,
  because the modules phone home by default and a reviewer will ask. The contract is
  `core/iac-rendering/references/avm.md`; each resource reference opens with the decision
  → module input table and the call, and keeps the authored rendering below it.
- **Module coordinates and versions stay in the renderer, never in the spec.** Versions
  are `0.y.z` and move monthly; they are looked up live (MCR tag list, module repo git
  tags) and pinned in the code. The tables in the references are dated snapshots.
- **One triggering skill, families as routing, question sets as knowledge.** The skill
  listing has a shared character budget and drops descriptions silently when it overflows.
  A skill per family overflowed at the sixth family.
- **Defaults from the guardrails, not the portal — and not the module.** AVM defaults
  diverge from the guardrails too (`Standard_GRS`, 365 days retention, infrastructure
  encryption off, public access on), so every decision is written on the call even where
  it matches.
- **Landing-zone model.** A workload lands in an application landing zone; the platform
  (hub, DNS zones, central workspace) exists and is referenced, never built.
- **Authored rendering references target `azurerm` 5.x.** `public_network_access` is a
  string there; the 4.x bool is deprecated and `validate` does not warn. The AVM Log
  Analytics module still pins `azurerm` 4.x, and the AzAPI-based AVM modules (storage,
  vnet) need `azapi`, `modtm`, `random` — the root's provider set is the union.
- **Plan-only tests mock the platform.** A referenced vnet or workspace is a `data` block,
  which a plan reads from Azure; `mock_provider "azurerm"` with parseable ids keeps the
  test credential-free. With a module in the middle, `azapi` and `modtm` are mocked the
  same way and the assert target is the module's `resource` output.
- **Sub-resource names go through `<?SUBNAME>`**, not appended to a finished name. The
  first cross-backend diff found the Terraform render naming a private endpoint
  `…-01-blob` while Bicep said `…-blob-01`; the convention has the token for exactly this.
- **Tests are part of the render, with coverage as the contract.** One assert per spec
  decision, named by its key path; a decision a plan cannot observe is marked with its
  reason. `Test-RenderCoverage.ps1` checks spec against tests, so "everything is tested"
  is a gate, not an intention. Bicep has no equivalent yet (see Open).
- **No registry alias, no registry modules — for the owner's own registry.** `br/public:`
  needs no alias and is the default; `br/modules:` is only rendered when
  `bicepconfig.json` already has it (`implementation: reuse`).

## Open

- **The example is still the authored render.** `private-storage-on-platform` predates
  AVM-first and now documents `implementation: authored`. Re-rendering it on
  `avm-res-storage-storageaccount` / `avm/res/storage/storage-account` is the next step,
  and it needs a machine with registry access (`registry.terraform.io`, `mcr.microsoft.com`,
  GitHub releases for the `naming` provider) — the session that wrote the AVM references
  had none, so the module calls in the references are written from the module READMEs and
  sources, not from a plan.
- **Which decisions a plan can observe through an AVM module's `resource` output** is
  undecided until that render: `avm.md` describes the intended test contract (assert on
  `resource.body` with `azapi` mocked, mark the rest `not-testable` with the module as the
  reason) and `Test-RenderCoverage.ps1` accepts either per decision.
- `Test-QuestionSet.ps1` is referenced by the authoring docs and not written.
- **Todo: an AVM version drift check.** The versions in `avm.md` and the six resource
  references are dated snapshots. A scheduled check that compares them against the MCR
  tag lists and the module repos' git tags and reports only what moved - never edits -
  would keep the tables honest. Checkable goal, read-only gate, the dated table as its
  memory; not set up yet (the owner's call, 2026-10-17).
- `patterns/` is empty; composition is specified on paper only. AVM pattern modules
  (`private-link-private-dns-zones`, `hub-networking`) are candidates for what a pattern
  skill wraps rather than re-implements.
- No render has been applied: neither `terraform plan` nor `what-if` has run against a
  subscription, so the renders are validated, not proven.
- The eval suite has no committed baseline yet; the first full run writes it. No eval
  grader checks `implementation` or `module_source` yet.
- Bicep renders have no tests. `bicep test` is experimental; the candidate is asserting on
  the compiled ARM JSON per decision, mirroring the tftest markers.
- Remaining families: `compute`, `data`, `security`. Key Vault's Terraform AVM module is
  `Orphaned` in the index — usable, flagged in the handover.

## Next

Re-render `private-storage-on-platform` on the AVM modules, both targets, from the
unchanged spec: `terraform init` with `azapi`/`modtm`/`random` added, `terraform test`
with the mocked providers, `Test-RenderCoverage.ps1`, `bicep build` against `br/public`.
That run settles the test contract in `avm.md`, re-measures the cross-backend diff (the
role GUID table and the two diagnostic settings should disappear from it), and is the
template for `greenfield-telemetry` — three resources, created network and workspace,
Bicep — which exercises the `create` branches the first example never reached.

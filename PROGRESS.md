# Progress

The handoff between sessions. Read it at the start of one, rewrite it at the end of one —
the goal rarely changes, the rest does. Keep it tight: what is here is what the next
session starts from, and what is not here it re-derives. The direction behind the next
thing is `ROADMAP.md`.

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
  same way and the assert target is the module's `resource` output — settled 2026-10-18
  on the storage module v0.10.0: the account body, identity, name and parent id are
  observable at plan time, the `private_endpoints` output gives name and a null zone
  group id; what the module builds in child modules (blob service, diagnostics, role
  assignments, the endpoint body) is not, and is marked not-testable — 9 of 24 storage
  decisions. The `resource` output is sensitive, so a failing assert prints
  `(sensitive value)`; the error message carries the expected value.
- **Sub-resource names go through `<?SUBNAME>`**, not appended to a finished name. The
  first cross-backend diff found the Terraform render naming a private endpoint
  `…-01-blob` while Bicep said `…-blob-01`; the convention has the token for exactly this.
- **Tests are part of the render, with coverage as the contract - both targets.** One
  assert per spec decision, named by its key path; a decision the target cannot observe
  is marked with its reason. Terraform asserts on the plan (`terraform test`); Bicep
  asserts on the compiled ARM (`tests/*.armtest.yaml`, `run_arm_tests.py`, 2026-10-18):
  a module call is a nested deployment whose parameter values are the decisions, a loop
  a `copy` whose expression text is matched by regex, symbolic resource names forced by
  `bicepconfig.json`. `check_render_coverage.py` checks spec against tests per target,
  so "everything is tested" is a gate, not an intention.
- **The interview is the customer's, alone.** Decided 2026-10-18: the person answering
  sits in front of the plugin without an engineer, so every question carries an
  `audience`, the customer answers about six requirement questions in their own words,
  technical decisions are derived from those (`source: requirement`), platform facts come
  from a `platform.yaml` (`source: platform`), and an engineer question nobody can answer
  becomes an `open:` entry instead of a question. Customer mode is the default; the
  engineer mode is entered on request or when the repository shows it. The plugin is
  public and has to hold for any use case. Beside the diagram, a decision document in the
  customer's language (Markdown first, Word offered once) is a deliverable. Plan:
  `ROADMAP.md`, phases A–E. B1 and B3 landed the same day: every one of the 82
  questions carries an `audience` (customer 13, engineer 49, platform 20) and
  `check_question_set.py` fails without one; `platform.yaml` is the engineer's profile
  (`references/platform.md`, a commented template beside it, `--platform` to check one),
  read at precedence 3 as `source: platform`, never written by an interview.
- **Requirements live in the deployment set, the map on the resource.** B2 and B4,
  2026-10-18. The three customer questions (`outage_impact`, `data_loss_tolerance`,
  `data_access_pattern`) are a `requirements` group in `deployment.yaml` rather than
  the separate `requirements.yaml` the roadmap named: one resolution mechanism, no
  second scope. A resource question derives through its own `derived_from: { question,
  map }`, so a new resource maps an existing requirement without touching the
  deployment set; the spec records `source: requirement` + `derived_from`, and the
  default answer derives the guardrail default so an unanswered requirement changes
  nothing. Both checks verify the map covers every answer. Customer questions in a
  run: environment, exposure, mandates, the three requirements, and log retention when
  the deployment owns the workspace - six, the budget. `iac-authoring` now has the two
  modes: customer (default; only `customer` questions asked, the rest resolved or
  opened) and engineer.
- **The decision document is rendered, not written.** B5, 2026-10-18. Every question
  carries `plain` (`en` and `de`, `{value}` where the value goes) and, where a raw value
  means nothing to a customer, `plain_values`; `export_decisions.py` turns a spec into
  `infra-decisions.md` in the customer's language - what follows from their answers with
  the derived decisions under each, what the rules set, departures, open items, an
  appendix with every key. Both examples carry theirs. Word is a `pandoc` conversion
  offered once in Phase 5, never a second source.
- **The stack is the default, and per-stage values are never literals.** Owner's call,
  2026-10-18: one code base goes through `development`, `test`, `production` unless the
  customer says otherwise ("nur prod", "Sandbox"); a request naming one stage names that
  stage of the stack. `context.environments` replaces `context.environment`; every value
  is one for all stages or a map keyed by stage, a stage nobody could answer for is an
  `open:` entry naming it, and a stage with open values gets no parameter file. A
  question with `per_environment: true` (ranges, prefixes, subscription, group,
  referenced platform parts) renders as a parameter with its value in
  `environments/<stage>.tfvars` / `main.<stage>.bicepparam`, one state per stage by
  backend key, never a workspace. Stages are separated by subscription by default
  (`stage_isolation`), resource groups being the lesser form. Parity between stages is
  the rule; `non_production_savings` (default enabled) lets `non_production_default`
  relax cost knobs - replication LRS, retention 30 - outside production, and the check
  refuses the field on anything security-shaped. Both examples re-rendered: the first
  with `environments/production.tfvars` and a development-stage test run, the second
  with `main.staging.bicepparam` and per-stage ARM assertions; the other stages are open.
- **`naming.yaml` is copied for Terraform only.** Owner's call, 2026-10-18: the provider
  reads it at plan time, nothing in a Bicep deployment does. A Bicep root gets its name
  vars generated from the plugin's convention and a `naming.yaml` only for a stated
  `custom` departure, holding the departures alone.
- **No registry alias, no registry modules — for the owner's own registry.** `br/public:`
  needs no alias and is the default; `br/modules:` is only rendered when
  `bicepconfig.json` already has it (`implementation: reuse`).

## Open

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
  grader checks `implementation` or `module_source` yet. The greenfield graders were
  corrected on 2026-10-18 (they predated the `standalone` default and expected `corp`
  with platform DNS); the suite has not run since.
- Remaining families, in the order `ROADMAP.md` C1 sets: `security` (Key Vault,
  user-assigned identity), `compute` (App Service, Container Apps), `data` (Azure SQL,
  PostgreSQL Flexible), `integration` (Service Bus). Key Vault's Terraform AVM module is
  `Orphaned` in the index — usable, flagged in the handover.
- **A sandbox subscription for real plans, applies and the deploy agent** (`ROADMAP.md`
  A5, E): the owner sets it up — subscription, federated credential for OIDC, a fenced
  resource group. Not available yet (2026-10-18).
- The customer interview (`ROADMAP.md` B), still open: the evals graders (B6) - a
  grader that counts the questions put to the customer and one that fails on Azure
  vocabulary in them. The decision document's `open:` lines stay English, because the
  spec's `open:` questions are English; a run translates them in the conversation.
- The stack's stage files are written only for resolved stages; nothing yet generates
  the other stages' files once their `open:` entries are answered - that is an extension
  run, and the first one has not been exercised.
- A cloud session needs `registry.terraform.io`, `releases.hashicorp.com`, `github.com`
  release downloads and `mcr.microsoft.com` allowed, and installs `terraform` and `bicep`
  into `~/.local/bin` itself (neither is in the image). Done once on 2026-10-18.

## Next

A4, the eval baseline: the suite's three cases now expect the stack, per-stage maps and
the derived values, and the plugin has never run against the current question sets; run
it, read the failed runs' specs before touching a grader, commit `baseline.json`. B6's two
graders (customer questions counted, no Azure vocabulary in them) go in with it. Then
`ROADMAP.md` C1: the `security` family (Key Vault, user-assigned identity) and `compute`
(App Service, Container Apps), each with `audience`, `plain`, `per_environment` where it
applies, both rendering references and a diagram icon. A5 waits on the owner's sandbox.

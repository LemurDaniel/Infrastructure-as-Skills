# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

A Claude Code **plugin** that authors Azure infrastructure as Terraform or Bicep. Not a
module library and not a template collection: the knowledge is shaped as **question sets** —
the decisions a resource forces, in YAML, each with the reasoning that justifies its default
and the attribute it renders to.

The reason for that shape: a storage account is not hard because the HCL is hard. It carries
about forty decisions, most invisible until something breaks, and generic code generation
gets the syntax right and the decisions wrong.

Two layers, plus a handover file:

| Layer | Role |
|---|---|
| **Resource families** (`resources/<family>/`) | Reference material, not skills. One directory per resource, its decisions in `<resource>/questions.yaml`; the `azure-resources` skill routes into them |
| **Pattern skills** (`patterns/`) | Pre-answer most of a resource's questions and own the wiring between the parts |
| **`infra-spec.yaml`** | The interview's output. A backend renders *from* it; it is not a by-product |

The sibling repo `../Infrastructure-by-Skill` points the other way: it drives a GUI through
an agent and records the run. The split is **not** "no API there, API here" — that repo is an
experiment and is deliberately run against systems that do have an API, because without a
comparable IaC path there is no baseline. Where both are possible, this repo is the
production answer and the other is the measurement.

## Commands

```powershell
# Pre-commit checks (read-only). Includes `claude plugin validate` on the plugin
# and the marketplace — it finds the CLI on PATH, or the binary the VS Code
# extension ships, and warns rather than passing quietly if it finds neither.
pwsh -NoProfile -File .claude/skills/git-commit-conventions/scripts/Test-RepoConsistency.ps1

# Validates a generated spec. -RequireApplyable also fails on assumed values and
# open items. Needs powershell-yaml or python with PyYAML.
pwsh -NoProfile -File plugins/infrastructure-as-skills/core/iac-authoring/scripts/Test-Spec.ps1 <spec>
```

There is no build and no test runner. The artefacts are Markdown and YAML, so these two
scripts are the whole verification story.

**`claude` is not on `PATH` on this machine.** The CLI lives at
`~/.vscode/extensions/anthropic.claude-code-*/resources/native-binary/claude.exe`; invoke
it by full path, or let the check script find it.

## Repository Layout

| Path | Role |
|---|---|
| `.claude-plugin/marketplace.json` | Marketplace manifest — this repo is its own marketplace |
| `plugins/infrastructure-as-skills/.claude-plugin/plugin.json` | Plugin manifest. The `skills` array is what makes the grouped layout work |
| `.../core/iac-authoring/` | The interview protocol: resolution order, what gets asked, the spec |
| `.../core/iac-authoring/questions/deployment.yaml` | The deployment-wide set: posture, network ownership, mandates. Resolved before any resource |
| `.../core/iac-authoring/references/spec.md` | `infra-spec.yaml` schema, the `source` field, `composition` |
| `.../core/iac-authoring/references/question-set-format.md` | How to author a resource's `questions.yaml` |
| `.../core/iac-authoring/references/guardrails.md` | The rules every question set takes its defaults from |
| `.../core/iac-rendering/` | The other side of the spec: how it becomes Terraform or Bicep |
| `.../core/iac-rendering/references/naming.md` | The Terraform and Bicep naming interfaces |
| `.../core/iac-rendering/references/{terraform,bicep}-idiom.md` | File layout, modules, variables, tagging, tests per target |
| `.../core/azure-resources/` | The single trigger for every resource: request → family. Its description is the keyword surface for all of them |
| `.../resources/<family>/routing.md` | Routing table: request → question set. **Not** a `SKILL.md` — see below |
| `.../resources/<family>/<resource>/questions.yaml` | **The content.** One per resource |
| `.../resources/<family>/<resource>/notes.md` | What the question set cannot express |
| `.../resources/<family>/<resource>/{terraform,bicep}.md` | The rendering per target |
| `.claude/skills/` | Repo maintenance. **Not** shipped with the plugin |

## The Two Structural Constraints

Both are easy to violate by accident and both fail quietly.

### One skill triggers every resource; families are not skills

Claude Code keeps every skill's name and description in context under a **shared character
budget** — about 1% of the model's context window — and drops descriptions when it overflows,
starting with the least-used skills. The name survives; the description does not, and the
description *is* the triggering mechanism. So the skill is installed, it appears in the
listing, and nothing matches it. Nothing tells you this happened.

A skill per resource would spend the budget at once. A skill per family was the first
answer and it did not hold: five skills cost 1,506 of ~2,000 characters, and the three
planned families would have put it at ~2,450 — overflowing on the plugin's own roadmap.
Hence three units: **`azure-resources` is the triggering unit, the family the routing unit,
the question set the knowledge unit.** Nothing is lost — question sets stay exactly as
specific as they would have been.

The single description can afford to be long: the per-entry cap is 1,536 characters, about
five family descriptions' worth, so one entry carries the keyword surface for every family
at a fifth of the cost. It is kept separate from `iac-authoring` on purpose — a keyword list
that grows with every family would otherwise crowd out the sentences describing the
protocol, inside the same cap. Past ~1,200 characters prune the least-typed terms; do not
split it, because a split is the per-family layout this replaced.

`/context` shows the listing size after the budget is applied and `/doctor` names the
biggest contributors.

### The groups are declared, not discovered

`core/` sits **beside** `skills/`, not inside it, and is declared in `plugin.json`:

```json
"skills": ["./core/"]
```

`resources/` is **deliberately undeclared**. Nothing in it is a skill, so nothing in it costs
listing budget; the azure-resources skill reads it by relative path. A family therefore has
a `routing.md`, never a `SKILL.md` — an undeclared directory holding a `SKILL.md` loads
nothing, and the consistency script fails on it.

Two reasons, both load-breaking if ignored:

- The `skills/` scan is **one level deep and does not recurse**. Nesting inside it loads
  nothing.
- The default `skills/` scan **cannot be switched off**, so a group folder placed inside it
  would be read as a skill without a `SKILL.md`.

A declared path that does not exist **fails to load the plugin**, which is why `./patterns/`
is absent from the array until it holds a skill. Add the entry in the same commit as the
first skill in that group.

## Gotchas

- **The two targets render names differently.** Terraform uses the `LemurDaniel/naming`
  provider with the `Azure::Microsoft.Storage/storageAccounts` identifier. Bicep assembles
  the name from `var`s in the template — the `utility/naming` modules and `genName` are
  **not ready to ship** and generated Bicep must never import them. Every question set
  declares the identifier, the plain Bicep resource type and the `abbreviation` the vars
  render — use those rather than constructing one.
- **The naming provider supersedes the two naming modules.** `LemurDaniel/naming` replaces
  `LemurDaniel/naming-schema/random` + `LemurDaniel/naming/random` — same engine, ported and
  tested against their fixtures. New generated code uses the provider; a repo already on the
  modules keeps them. Never mix both in one configuration.
- **A `CLAUDE.md` inside the plugin directory is not loaded as context** and
  `claude plugin validate` warns about it. Instructions that must reach Claude belong in a
  skill. This file is at the repo root, which is a normal project `CLAUDE.md` and does load.
- **Frontmatter `name` must equal the skill's directory name.** A mismatch is accepted and
  then behaves unpredictably.
- **The spec names decisions, not attributes.** `public_network_access: disabled`, never
  `public_network_access_enabled: false` — the latter is `azurerm`'s spelling and leaks one
  backend's vocabulary into the interface the other backends read.
- **Defaults come from the guardrails, not from the Azure portal.** They diverge routinely
  and in the same direction: public network access, shared-key auth and anonymous blob access
  all ship enabled. Inheriting that is how exposure findings happen.
- **A decision that holds for more than one resource belongs in the deployment set.** The
  test is whether two resources could sensibly answer it differently. Exposure, network
  ownership, key protection and the diagnostics destination cannot; a resource question
  that re-asks one of them carries `from_deployment` instead of a `default`.
- **A missing question set is said out loud, never improvised.** Generating a resource from
  generic rules while the routing table claims a question set backs it removes the one
  property that makes this plugin worth using, silently.

## Status

Early, and deliberately honest in `README.md` about what is unproven:

- `Test-Spec.ps1` exists at `core/iac-authoring/scripts/` and needs a YAML parser
  (`powershell-yaml`, or python with PyYAML); without one it exits 2 rather than passing a
  file it could not read. `Test-QuestionSet.ps1` is still referenced and **not written** —
  `Test-RepoConsistency.ps1` covers part of what it would.
- `patterns/` is empty, so composition is specified on paper only.
- Three resources exist: `storage/storage-account`, `network/virtual-network`,
  `observability/log-analytics-workspace`. The last two were written because a test run
  produced a spec that could not be rendered without them.
- No spec has been rendered to Terraform or Bicep yet. The interview and the spec are
  exercised; the renderer is not.

## Repository Conventions

[.claude/skills/git-commit-conventions/](.claude/skills/git-commit-conventions/SKILL.md)
carries the working rules — read it before committing. In short: commits carry **no
attribution trailers** (no `Co-Authored-By`, no "Generated with Claude Code"); English
imperative subject; one concern per commit; default branch is `master`.

The `origin` remote URL embeds a GitHub personal access token — never copy a remote URL into
a tracked file, a commit message, or command output you paste back.

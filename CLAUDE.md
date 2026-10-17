# CLAUDE.md

Guidance for Claude Code when working in this repository. `PROGRESS.md` holds the state
between sessions — read it first, rewrite it last. `README.md` holds the pitch and the
status; neither is repeated here.

## What This Repo Is

A Claude Code **plugin** that authors Azure infrastructure as Terraform or Bicep. Not a
module library and not a template collection: the knowledge is shaped as **question sets** —
the decisions a resource forces, in YAML, each with the reasoning that justifies its default
and the attribute it renders to. A storage account is not hard because the HCL is hard; it
carries about forty decisions, and generic generation gets the syntax right and the
decisions wrong.

| Layer | Role |
|---|---|
| **Resource families** (`resources/<family>/`) | Reference material, not skills. One directory per resource, its decisions in `<resource>/questions.yaml`; the `azure-resources` skill routes into them |
| **Pattern skills** (`patterns/`) | Pre-answer most of a resource's questions and own the wiring between the parts |
| **`infra-spec.yaml`** | The interview's output. A backend renders *from* it; it is not a by-product |

## Commands

```powershell
# Pre-commit checks (read-only). Includes `claude plugin validate` on the plugin
# and the marketplace — it finds the CLI on PATH, or the binary the VS Code
# extension ships, and warns rather than passing quietly if it finds neither.
pwsh -NoProfile -File .claude/skills/git-commit-conventions/scripts/Test-RepoConsistency.ps1

# Validates a generated spec. -RequireApplyable also fails on assumed values and
# open items. Needs powershell-yaml or python with PyYAML.
pwsh -NoProfile -File plugins/infrastructure-as-skills/core/iac-authoring/scripts/Test-Spec.ps1 <spec>

# A rendered example: fmt, validate, plan-only tests with a mocked platform - and the
# Bicep render of the same spec compiled and linted.
terraform -chdir=examples/private-storage-on-platform init && terraform -chdir=examples/private-storage-on-platform test
# Every decision in the spec asserted by those tests, or marked not-testable with a reason.
pwsh -NoProfile -File plugins/infrastructure-as-skills/core/iac-rendering/scripts/Test-RenderCoverage.ps1 examples/private-storage-on-platform/infra-spec.yaml
bicep build --stdout examples/private-storage-on-platform/bicep/main.bicep > $null && bicep lint examples/private-storage-on-platform/bicep/main.bicep
```

There is no build. The artefacts are Markdown and YAML; the scripts and the examples'
Terraform tests are the whole verification story.

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
| `.../core/iac-diagram/` | The spec as an editable draw.io PNG for the customer |
| `.../core/azure-resources/` | The single trigger for every resource: request → family. Its description is the keyword surface for all of them |
| `.../resources/<family>/routing.md` | Routing table: request → question set. **Not** a `SKILL.md` — see below |
| `.../resources/<family>/<resource>/questions.yaml` | **The content.** One per resource |
| `.../resources/<family>/<resource>/notes.md` | What the question set cannot express |
| `.../resources/<family>/<resource>/{terraform,bicep}.md` | The rendering per target |
| `.../evals/` | `claude plugin eval` cases; graders read the spec |
| `examples/<case>/` | A request, its spec and its render, end to end. What good looks like |
| `.claude/skills/` | Repo maintenance. **Not** shipped with the plugin |

## The Two Structural Constraints

Both are easy to violate by accident and both fail quietly.

### One skill triggers every resource; families are not skills

Claude Code keeps every skill's name and description in context under a **shared character
budget** — about 1% of the model's context window — and drops descriptions when it overflows,
starting with the least-used skills. The name survives; the description does not, and the
description *is* the triggering mechanism. So the skill is installed, it appears in the
listing, and nothing matches it. Nothing tells you this happened.

A skill per family was the first answer and it did not hold: five skills cost 1,506 of
~2,000 characters. Hence three units: **`azure-resources` is the triggering unit, the
family the routing unit, the question set the knowledge unit.**

The single description can afford to be long (per-entry cap 1,536 characters) and is kept
separate from `iac-authoring` on purpose. Past ~1,200 characters prune the least-typed
terms; never split it. `/context` shows the listing size after the budget is applied.

### The groups are declared, not discovered

`core/` sits **beside** `skills/`, not inside it, and is declared in `plugin.json` as
`"skills": ["./core/"]`. `resources/` is **deliberately undeclared**: nothing in it is a
skill, so nothing in it costs listing budget. A family has a `routing.md`, never a
`SKILL.md` — an undeclared directory holding one loads nothing, and the consistency script
fails on it.

- The `skills/` scan is **one level deep and does not recurse**, and it **cannot be
  switched off** — a group folder inside it is read as a skill without a `SKILL.md`.
- A declared path that does not exist **fails to load the plugin**, which is why
  `./patterns/` is absent from the array until it holds a skill. Add the entry in the same
  commit as the first skill in that group.

## Gotchas

- **The two targets render names differently.** Terraform uses the `LemurDaniel/naming`
  provider with the `Azure::Microsoft.Storage/storageAccounts` identifier. Bicep assembles
  the name from `var`s — the `utility/naming` modules and `genName` are **not ready to
  ship** and generated Bicep must never import them. Every question set declares the
  identifier, the Bicep resource type and the `abbreviation`; use those.
- **The naming provider supersedes the two naming modules.** New generated code uses the
  provider; a repo already on the modules keeps them. Never mix both in one configuration.
- **Rendering references target `azurerm` 5.x.** `public_network_access = "Disabled"`
  (string); the 4.x bool is deprecated and `validate` does not warn. Check arguments against
  `terraform providers schema -json` rather than memory.
- **A `CLAUDE.md` inside the plugin directory is not loaded as context.** Instructions that
  must reach Claude belong in a skill. This file is at the repo root and does load.
- **Frontmatter `name` must equal the skill's directory name.**
- **The spec names decisions, not attributes.** `public_network_access: disabled`, never
  `public_network_access_enabled: false` — that is one backend's spelling leaking into the
  interface the others read.
- **Defaults come from the guardrails, not from the Azure portal.** They diverge routinely
  and in the same direction.
- **A decision that holds for more than one resource belongs in the deployment set.** A
  resource question that re-asks one carries `from_deployment` instead of a `default`.
- **A missing question set is said out loud, never improvised.**
- **A Terraform render ships with its tests.** One `assert` per spec decision, named
  `# decision: <resource>.<group>.<question>`; what a plan cannot observe is
  `# not-testable:` with a reason. `Test-RenderCoverage.ps1` fails on anything else.
- **`Test-QuestionSet.ps1` does not exist yet** although the authoring docs name it.
  `Test-RepoConsistency.ps1` covers part of what it would.

## Repository Conventions

[.claude/skills/git-commit-conventions/](.claude/skills/git-commit-conventions/SKILL.md)
carries the working rules — read it before committing. In short: commits are authored as
**LemurDaniel \<landau.daniel.1998@gmail.com\>** (set repo-locally only in a tool-driven
session whose identity starts as `Claude`; never touch a configured identity on the
owner's machine); they carry **no attribution trailers** (no `Co-Authored-By`, no "Generated
with Claude Code"); English imperative subject; one concern per commit; default branch is
`master`; `PROGRESS.md` is rewritten before a session's last commit.

`.claude/settings.json` pre-approves the read-only checks and denies force-push,
`reset --hard`, `--no-verify` and `terraform apply`. Do not widen it from a session.

The `origin` remote URL embeds a GitHub personal access token — never copy a remote URL into
a tracked file, a commit message, or command output you paste back.

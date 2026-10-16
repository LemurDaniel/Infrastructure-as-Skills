---
name: iac-authoring
description: The shared contract behind every skill here — how a question set becomes infra-spec.yaml, which questions are asked versus silently defaulted, and the Terraform and Bicep idioms the generated code follows. Read before rendering any Azure resource or pattern, when extending a question set, or when asked how this plugin works or why a default was chosen.
---

# Authoring infrastructure from a question set

Each resource family skill carries a question set per resource under `questions/`: the
decisions that resource forces, grouped by concern. This file is the protocol for turning a
question set into a spec, and the spec into code. Follow it rather than improvising — the
value of the plugin is that two runs of the same skill ask the same things and record them
the same way.

The family is the **triggering** unit and the question set is the **knowledge** unit. They
are separate because the skill listing has a shared character budget: a skill per Azure
resource would spend it all and get its own descriptions dropped, which silently removes
the keywords that make any of it discoverable.

## The pipeline

```
question set  ──interview──>  infra-spec.yaml  ──render──>  Terraform / Bicep  ──validate──>  explained plan
```

The spec in the middle is the load-bearing part. It is the handover interface, not a
by-product: a backend renders *from* it, and the same spec can go to a different backend —
including `Infrastructure-as-Skills` for API-driven execution — which is what makes the two
tracks comparable at all. Never generate code directly from the interview.

## Phase 1 — Establish the target

Terraform or Bicep. Do not ask if the repository answers it:

- `*.tf` or `.terraform.lock.hcl` present → Terraform
- `*.bicep` or `bicepconfig.json` present → Bicep
- both, or neither → then ask, once

## Phase 2 — Resolve every question

For each question, the answer comes from the first source that has one:

| # | Source | `source` recorded as |
|---|---|---|
| 1 | What the user already said in their request | `stated` |
| 2 | A pattern skill's pre-answers | `pattern` |
| 3 | An existing `infra-spec.yaml` in the target directory | `carried` |
| 4 | The question's `default` | `default` |

A question with `required: true` has no default and no safe guess. It is the only kind you
must ask.

Defaults are not invented per resource — they come from
[azure-guardrails](../azure-guardrails/SKILL.md), which is also where their reasoning
lives. Read it before choosing any default or justifying one.

## Phase 3 — Ask, in one batch

Collect every question that survived resolution and put them in a single exchange. Where
the host offers `AskUserQuestion`, use it — grouped options with the trade-off in the
description beat prose.

A serial interrogation ("and now, the TLS version?") is the one failure mode that makes
people abandon a tool like this, and it is entirely avoidable: the question set is known up
front, so there is no reason to discover questions one at a time.

If more than about six questions survive, you are asking things that should have defaults.
Say so and propose the defaults instead.

A question may carry `confirm_in: [production]`. Its default still applies, but in that
environment you surface it for confirmation rather than applying it silently — these are
the values whose blast radius makes a silent default inappropriate.

## Phase 4 — Report what was defaulted, before generating

Show a compact account. Not forty rows — group it:

```
Defaulted (guardrail baseline):
  Security        TLS 1.2 floor, shared-key auth off, infrastructure encryption on
  Data protection blob soft-delete 7d, container soft-delete 7d, versioning on
  Observability   diagnostics -> Log Analytics, categories: audit + allLogs

Asked:
  environment     production
  location        westeurope
  exposure        private endpoint in snet-data-prod-01
```

This is the step that keeps the plugin honest. Someone who disagrees with a default needs
to see it to disagree with it, and the ones they never look at cost one glance.

## Phase 5 — Write the spec, then render

Write `infra-spec.yaml` first, then render from it. Doing it in that order is not
bookkeeping: it forces the decisions to be expressible in the backend-neutral vocabulary,
and a decision that will not fit is usually one that absorbed a backend's spelling.

- Spec schema and the `source` field: [references/spec.md](references/spec.md)
- Terraform rendering: [references/terraform-idiom.md](references/terraform-idiom.md)
- Bicep rendering: [references/bicep-idiom.md](references/bicep-idiom.md)

## Phase 6 — Validate and explain

Generated code is not done when it is syntactically valid. Hand off to
[iac-plan-review](../iac-plan-review/SKILL.md) for the full sequence; the short version is
`fmt` → `validate` → `plan` / `what-if` → policy scan → explain what will actually happen
and what is risky about it.

Do not skip the explanation on the grounds that the plan output is right there. A plan is a
list of attribute diffs; what a reviewer needs is which of those diffs are
service-affecting and which are noise, and that is a judgement the plan cannot make.

## Do not invent attributes

A plausible-looking argument that does not exist is worse than asking. Provider schemas
move, and exact spellings are not something to recall from memory.

- **Terraform** — `terraform providers schema -json` in the target directory (needs
  `terraform init`). Narrow it with `jq`; it is megabytes.
- **Bicep** — compile early: `bicep build --stdout <file>` fails loudly on an unknown
  property, which is faster than reasoning about it. For API versions, prefer the version
  already used elsewhere in the repository over the newest one you can think of.

When neither is available and you are unsure, name the attribute you are unsure about
instead of guessing. A named uncertainty is cheap to resolve; a wrong argument found at
apply time is not.

## Composition: how a pattern drives a resource

A pattern skill does not re-ask a resource's questions. It supplies a pre-answer block
keyed by resource skill, entering resolution at precedence 2:

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
  assignments between the parts, diagnostic routing: no single resource skill can own a
  relationship, so the pattern renders it. This is the genuinely hard part and the main
  reason pattern skills exist.

## Adding a resource

A resource goes into an existing family skill — `storage`, `network`, `compute`, `data`,
`security`, `observability` — not into a skill of its own. Inside that family:

1. Write `questions/<resource>.yaml`. Copy an existing one and keep the group order:
   placement, networking, identity, security, data_protection, observability. The order is
   the review order, and a reviewer reading three resources should not relearn the layout.
2. Fill `why` and `renders` for every question. `why` is what a reviewer reads; `renders`
   names the attribute it drives, which is what lets a review map code back to a decision.
3. Take defaults from [azure-guardrails](../azure-guardrails/SKILL.md) rather than from the
   Azure portal. They differ often, and the portal default is not a baseline worth
   inheriting.
4. Mark `required: true` only where no safe default exists. Every extra required question
   is a tax on every future run.
5. Write `references/<resource>/notes.md` for what the question set cannot express:
   decisions fixed at creation, dependency order, the pitfalls worth naming out loud.
6. Write `references/<resource>/terraform.md` and `references/<resource>/bicep.md` — the
   rendering, not the decisions. Anything true for both belongs in the shared references
   instead.
7. Add a row to the family skill's routing table, so the resource is reachable.
8. Validate: `pwsh -NoProfile -File scripts/Test-QuestionSet.ps1 <family-dir>`

A genuinely new family — a cloud or a domain none of the existing ones covers — gets its
own skill directory and an entry in `plugin.json`'s `skills` array. Weigh it against the
listing budget first: each family skill spends part of a shared allowance, and the cost of
one too many is that descriptions get dropped from skills you did not touch.

## Reference files

Read as needed, not up front:

| File | When |
|---|---|
| [references/naming.md](references/naming.md) | Always, before rendering a name — the two targets' identifier syntax differs |
| [references/spec.md](references/spec.md) | Writing or reading `infra-spec.yaml` |
| [references/terraform-idiom.md](references/terraform-idiom.md) | Rendering Terraform |
| [references/bicep-idiom.md](references/bicep-idiom.md) | Rendering Bicep |
| [references/question-set-format.md](references/question-set-format.md) | Authoring or extending a `questions.yaml` |
| [azure-guardrails](../azure-guardrails/SKILL.md) | Choosing or justifying any default |
| [iac-plan-review](../iac-plan-review/SKILL.md) | After rendering: validate, policy-scan, explain |

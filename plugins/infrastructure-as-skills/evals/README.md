# Evals

End-to-end cases for `claude plugin eval`: a request goes in, the plugin interviews,
writes `infra/infra-spec.yaml`, draws it, validates it — and the graders check the spec.

```powershell
claude plugin eval plugins/infrastructure-as-skills --allow-tools Write Edit
```

`Write` and `Edit` are needed because the run writes the spec. No shell: on Windows the
eval sandbox has no backend and refuses any case that grants one, so `Test-Spec.ps1` and the
diagram run outside the suite. How to run, check and read the suite is in the repo's
`plugin-evals` skill (`.claude/skills/plugin-evals/`). Results land in `evals/results/`,
which is ignored.

## The cases

Chosen along the dimensions where this plugin can go wrong, so three cases cover the
most different situations rather than three variations of one:

| Case | Target | Env | Exposure | Network | Workspace | Scenario |
|---|---|---|---|---|---|---|
| `private-storage-on-platform` | Terraform | production | private | **reference** | **reference** | Complete description, mandate, existing platform |
| `greenfield-telemetry` | Bicep | staging | private | **create** | **create** | Three resources, given ranges, stated retention |
| `vague-public-dev` | Terraform | development | public | none | reference | **Missing information** |

Every case ends the same way, so every case can be graded the same way: no one answers
follow-up questions (a headless run cannot), and neither a diagram nor code is wanted —
only the spec.

## What the graders check

Mostly `regex` over `infra/infra-spec.yaml`. A regex reads the whole file identically every
run, costs nothing, and its failure says exactly which decision went wrong. Each case has:

- **The decisions the prompt settled** — exposure, ownership, ranges, retention.
- **What must not appear** — a created vnet that was only referenced, an invented address
  range, subscription id or resource group. These are the failures that look plausible and
  surface at apply time, which is why they are weighted up.
- **The process** — `Skill` fired (an indicator, not scored against the no-plugin arm),
  `naming.yaml` written, no `.tf`/`.bicep` written before confirmation.

`Test-Spec.ps1` — the contract check covering sources, enums, backend attribute spellings
and composition — runs on the produced specs after the suite, not inside it.

One `llm` grader, in `vague-public-dev`, on the short final message only, with concrete
PASS and FAIL conditions.

## Keeping outputs good on the same scenarios

`runs: 3` per case is the consistency measurement: a grader that passes in two of three
runs is a decision the plugin does not pin down. Read those first — they are where a
question set lacks a default, a rule in `iac-authoring` is ambiguous, or the
description-to-spec mapping in Phase 0 guesses.

The method follows Hamel Husain's
[*Creating a LLM-as-a-Judge That Drives Business Results*](https://hamel.dev/blog/posts/llm-judge/):

1. **One expert decides what good is** — the repository owner, not a generic metric.
2. **Binary pass/fail with a written critique**, never a 1–5 score. A critique detailed
   enough for a new colleague becomes the next grader or the next guardrail.
3. **Read the traces.** After a run, open the report and read the failed runs' specs before
   touching a grader. Group failures by cause and fix the most frequent first — usually in
   the plugin, not in the eval.
4. **Code checks before judges.** Anything expressible as a regex over the spec is one.
   Add an `llm` grader only for what a regex cannot see, and only after checking its
   verdicts against your own on a handful of runs — agreement on both passes and fails,
   not overall agreement.
5. **Every fixed failure becomes a case.** A bug found in a real run (like the
   `name / resource-group` label overflow) gets a case or a grader, so it stays fixed.

Re-run the suite after any change to a question set, the guardrails or `iac-authoring`,
and after a model update — and compare against `baseline.json`, the committed pass rates
of the last accepted run. `Show-EvalResult.ps1` does the comparison and flags a grader
whose rate dropped as REGRESS; `-UpdateBaseline` writes the new snapshot once the run is
read and accepted. Results stay ignored; the baseline is the one thing a run leaves
behind in git.

## Adding a case

Pick a combination the table does not have yet — a pattern skill once `patterns/` exists,
an extension run (a scaffolded repo that already holds a spec), a `custom` naming
convention, a user who contradicts themselves. Write the prompt as a real user would,
then one grader per decision the prompt settles and one per value it must not invent.

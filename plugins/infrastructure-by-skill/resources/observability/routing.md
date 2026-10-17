---
name: observability
description: Azure monitoring resources as Terraform or Bicep — Log Analytics workspaces, with the retention, ingestion-cost and access decisions each forces. Use for a workspace, log retention or diagnostic routing, and when a deployment has to build its own monitoring rather than reference a platform one.
---

# Azure observability resources

Routing table — the request picks the question set:

| Request mentions | Question set | Notes |
|---|---|---|
| Log Analytics, workspace, log retention | `questions/log-analytics-workspace.yaml` | [notes](references/log-analytics-workspace/notes.md) |
| Application Insights, APM, traces | *not yet written* | Workspace-based now; needs a workspace first |
| alert, action group, metric alert | *not yet written* | — |
| dashboard, workbook | *not yet written* | — |

When a question set does not exist yet, say so rather than improvising one. Fall back to
[the guardrails](../../core/iac-authoring/references/guardrails.md), generate from those
rules, and record in the spec that no question set backed it.

## Then

1. [iac-authoring](../../core/iac-authoring/SKILL.md) — the interview protocol, and
   [the deployment set](../../core/iac-authoring/questions/deployment.yaml), where
   `observability_ownership` already decided whether this resource is created at all
2. [iac-rendering](../../core/iac-rendering/SKILL.md) — the spec into Terraform or Bicep

## True for the whole family

**Most deployments should reference a workspace, not create one.** A workspace per
deployment fragments exactly the correlation an incident needs — the question "what else
was happening at 03:14" cannot be answered across six workspaces. `create` is for an
isolated environment with no platform workspace to point at, and the deployment set
settles that before this resource is reached.

**Retention is the cost decision, and it is billed twice.** Ingestion is charged per
gigabyte on the way in; retention beyond the free period is charged per gigabyte per month
after that. The failure mode is not an expensive workspace — it is someone turning
logging off to stop the bill, which costs more the first time it matters.

**Deleting a workspace is soft for 14 days** and the name stays reserved for that period.
A recreate with the same name inside the window fails or recovers the old one, which is
confusing in both directions; `terraform destroy` followed immediately by `apply` is where
this shows up.

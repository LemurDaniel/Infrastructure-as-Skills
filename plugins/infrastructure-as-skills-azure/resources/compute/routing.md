# Azure compute resources

A resource family, reached from the [azure-resources](../../core/azure-resources/SKILL.md)
skill. Routing table - the request picks the question set:

| Request mentions | Question set | Notes |
|---|---|---|
| App Service, web app, App Service plan, webapp, azurewebsites | `app-service/questions.yaml` | [notes](app-service/notes.md) |
| function app, Azure Functions, Flex Consumption | `function-app/questions.yaml` | [notes](function-app/notes.md) - same module as App Service, `kind: functionapp` |
| Container Apps, container app environment, containerapp | `container-apps/questions.yaml` | [notes](container-apps/notes.md) - environment and one app |
| Container Registry, ACR, image registry | `container-registry/questions.yaml` | [notes](container-registry/notes.md) |
| AKS, Kubernetes | *not yet written* | — |
| virtual machine, VM, scale set | *not yet written* | — |
| deployment slot, autoscale, custom domain | *not yet written* | Decisions of an existing app; listed as boundaries of the App Service set |

When a question set does not exist yet, say so rather than improvising one. Fall back to
[the guardrails](../../core/iac-authoring/references/guardrails.md), generate from those
rules, and record in the spec that no question set backed it.

## Then

1. [iac-authoring](../../core/iac-authoring/SKILL.md) - the interview protocol, and
   [the deployment set](../../core/iac-authoring/questions/deployment.yaml), which already
   answers exposure, network ownership and the diagnostics destination before this set runs
2. [iac-rendering](../../core/iac-rendering/SKILL.md) - the spec into Terraform or Bicep

## True for the whole family

**Compute is where the other families' decisions land.** An app is reached through a
private endpoint and reaches out through a network integration; it logs to the workspace;
it holds an identity that other resources grant roles to. Almost every decision in an
App Service set is inherited from the deployment set or derived from a requirement, and
the few that are the app's own (runtime, size, health check) are an engineer's. A customer
is asked nothing new by this family.

**Inbound and outbound are separate features** with separate subnets: the private endpoint
sits in the platform's endpoint subnet, the VNet integration in a subnet delegated to the
plan. Asking only one is the common half-answer.

**The plan is the cost and the app is the workload.** Size, zone redundancy and instance
count belong to the plan and are billed per instance whether or not the app is busy; the
app's decisions cost nothing by themselves. A plan can host several apps, and this set
renders one plan per app - sharing a plan is wiring, owned by a pattern.

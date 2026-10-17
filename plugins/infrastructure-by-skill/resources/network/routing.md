---
name: network
description: Azure networking resources as Terraform or Bicep — virtual networks and subnets, with the address planning, delegation and private-endpoint policy decisions each forces. Use for a vnet, subnet, address space or private endpoint placement, and when a deployment has to build its own network.
---

# Azure network resources

Routing table — the request picks the question set:

| Request mentions | Question set | Notes |
|---|---|---|
| virtual network, vnet, address space, subnets | `questions/virtual-network.yaml` | [notes](references/virtual-network/notes.md) |
| network security group, NSG, security rules | *not yet written* | A separate resource; the vnet set only records which subnets expect one |
| peering, hub, spoke | *not yet written* | Needs both sides; usually a pattern, not a resource |
| route table, UDR, forced tunneling | *not yet written* | — |
| NAT gateway, outbound | *not yet written* | — |

When a question set does not exist yet, say so rather than improvising one. Generating a
resource without its decision set is how this plugin loses the property that makes it worth
using. Fall back to [the guardrails](../../core/iac-authoring/references/guardrails.md),
generate from those rules, and record in the spec that no question set backed it.

## Then

1. [iac-authoring](../../core/iac-authoring/SKILL.md) — the interview protocol, and
   [the deployment set](../../core/iac-authoring/questions/deployment.yaml), which already
   answers `network_ownership` and the address space before this set runs
2. [iac-rendering](../../core/iac-rendering/SKILL.md) — the spec into Terraform or Bicep

## True for the whole family

**The address space is the one decision that cannot be fixed later.** Every other property
of a network is editable in place; its range is not, because every subnet carved out of it
has to be emptied and rebuilt. A guess that nobody rejected is still a guess — ask the
owner, or record it as `open` and stop.

**A subnet is not an independent resource in practice.** Azure lets you manage subnets
inline in the vnet or as separate resources, and mixing both in Terraform makes the two
fight on every apply — `azurerm_subnet` plus a `subnet` block in `azurerm_virtual_network`
is the classic plan-churn bug. Pick one per configuration; this family renders them as
separate resources.

**Deleting a subnet that holds a private endpoint fails**, and the error names the
endpoint rather than the dependency. Ordering is the thing to get right the first time.

**Service endpoints and private endpoints are not two strengths of the same thing.** A
service endpoint keeps the resource publicly addressable and an ACL refuses traffic; a
private endpoint removes the public surface. The posture ladder is in the guardrails.

## Adding a resource to this family

Same steps as any family — see
[iac-authoring](../../core/iac-authoring/SKILL.md#adding-a-resource). Do **not** add a new
skill per resource: the listing budget is shared, and the family is the triggering unit.

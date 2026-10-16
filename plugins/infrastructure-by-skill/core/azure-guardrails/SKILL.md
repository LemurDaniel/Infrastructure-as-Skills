---
name: azure-guardrails
description: The central Azure rules every question set takes its defaults from — CAF naming, the mandatory tag set, no public network access, RBAC over access keys, encryption and key management, diagnostic routing. Read before choosing or justifying any default, when a resource seems to need an exception, and when reviewing Terraform or Bicep for compliance with these rules.
---

# Azure guardrails

The rules that hold across every resource, so no question set has to restate them and no
two restate them differently. A resource skill's `questions.yaml` sets defaults *from*
these rules; this file is where the reasoning lives.

Shared deliberately with `Infrastructure-as-Skills`: a GUI-driven run and a generated
Terraform run should reach the same posture, or the comparison between the two tracks
measures the wrong thing.

## 1. Naming

Never hardcode or assemble a resource name. Both backends have a schema-driven engine that
resolves the CAF convention, and the convention lives in exactly one place.

The mechanics, and the identifier syntax that differs between Terraform and Bicep, are in
[../iac-authoring/references/naming.md](../iac-authoring/references/naming.md). Read it
before rendering a name — the `Azure::` prefix trap catches every first attempt.

## 2. Tags

Four tags are mandatory on every resource that supports them:

| Tag | Value |
|---|---|
| `environment` | The spec's `context.environment` |
| `workload` | The spec's `context.workload` |
| `managed_by` | `terraform` or `bicep` — whichever generated it |
| `cost_center` | Required in `production`, optional elsewhere |

Applied from one merged local or variable, never written per resource. A resource with
hand-written tags will drift from its siblings the first time the set changes.

Resist adding more. Tags that encode something queryable from the resource itself — region,
SKU, resource type — go stale and then actively mislead. `owner` is the usual mistake: it
names a person who changes jobs, where a team or a service principal does not.

## 3. Network exposure

**Default to no public network access.** Every resource that can be reached privately is
generated that way, and public exposure is a decision somebody makes explicitly.

The posture ladder, in order of preference:

1. **Private endpoint** — the resource has no public surface. Costs an endpoint and a DNS
   zone entry, which is the price of the posture.
2. **Service endpoint / allowed subnets** — cheaper, but the resource is still publicly
   addressable and relies on an ACL to refuse traffic.
3. **Public with a firewall allowlist** — acceptable for a dev environment or where the
   consumer genuinely lives off-network. The allowlist must be enumerated; `0.0.0.0/0` in
   a firewall rule is not an allowlist.
4. **Public, unrestricted** — only with a stated reason recorded in the spec as
   `overridden`.

Private DNS zones are shared infrastructure. No resource skill creates one — a pattern
skill or the platform owns them, because two resource skills each creating
`privatelink.blob.core.windows.net` is a conflict that only shows up at apply time.

## 4. Identity over keys

**Managed identity and RBAC, not connection strings and access keys.** Where a resource
supports disabling local auth, disable it:

| Resource | The switch |
|---|---|
| Storage account | `shared_access_key_enabled: false` |
| Key Vault | `rbac_authorization: true` (not access policies) |
| Service Bus / Event Hub | local auth disabled |
| Cosmos DB | local auth disabled |
| SQL | Entra-only authentication |

System-assigned identity by default. Reach for user-assigned when an identity must outlive
a single resource or be shared across several — pre-assigning permissions before a resource
exists is the usual legitimate reason.

Role assignments are scoped as tightly as the consumer allows: the specific container or
secret, not the subscription. A role assignment at subscription scope in generated code is
a bug unless the resource genuinely operates subscription-wide.

## 5. Encryption

Platform-managed keys are the default, and that is not a compromise — they are encrypted,
rotated and free, and the operational burden of customer-managed keys is real.

Customer-managed keys are warranted when a compliance regime names them, or when key
revocation needs to be a capability you actually hold. Choosing them pulls in a Key Vault
with purge protection, an identity with wrap/unwrap, and a rotation story. If the spec
asks for CMK without those, the answer is incomplete rather than ready.

Encryption in transit is never negotiable: TLS 1.2 as the floor, HTTPS-only where the
resource has the switch.

## 6. Diagnostics

Every resource routes diagnostics somewhere. A resource with no diagnostic setting is
invisible exactly when someone needs to see it.

- **Destination**: a Log Analytics workspace by default. A storage account only for
  long-retention archival, and then alongside the workspace, not instead of it.
- **Categories**: audit categories always. `allLogs` in non-production and for anything
  handling regulated data; be deliberate in production where volume has a price.
- **Metrics**: `AllMetrics`, which is cheap.

The workspace is shared infrastructure, like DNS zones — referenced, not created, by a
resource skill.

## 7. Exceptions

A guardrail that cannot be departed from gets worked around instead of discussed, which is
worse. So exceptions are allowed, and the cost is recording them:

- The spec records the value with `source: overridden` and a comment stating the reason.
- Generated code carries a comment at the departing attribute pointing at that reason.
- In `production`, the exception is confirmed explicitly during the interview rather than
  applied from a previous spec.

What is not allowed is a silent exception. If a generated resource departs from these rules
and nothing says why, that is the defect — not the departure.

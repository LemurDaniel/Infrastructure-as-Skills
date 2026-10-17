# The guardrails every default comes from

The rules that hold across every resource, so no question set has to restate them and no
two restate them differently. A resource's `questions/<resource>.yaml` sets its defaults
*from* these rules; this file is where the reasoning lives. Read it before choosing a
default, before justifying one, and when a resource seems to need an exception.

They are **not** the Azure portal's defaults. The two diverge routinely and in the same
direction — public network access, shared-key auth and anonymous blob access all ship
enabled — so inheriting the portal's posture is how an exposure finding happens.

Shared deliberately with `Infrastructure-as-Skills`: a GUI-driven run and a generated
Terraform run should reach the same posture, or the comparison between the two tracks
measures the wrong thing.

## 1. Naming and tags

Never hardcode a resource name, and never hand-write a tag per resource. Both are
mechanical rules; **neither prescribes content.**

Which tags exist is an organisation's decision, not this plugin's. Take the set from the
repository — an existing `locals.tags`, a `var tags` in `main.bicep`, what the resources
already carry — and apply the same one. Where the repository has none and the user has not
said, ask once and record the answer in the spec's `context.tags`, which is then what every
resource gets. A tag set invented by a generator is a tag set nobody queries.

The applying is the mechanical part: one merged local or variable, passed everywhere. A
resource with its own tag literal drifts from its siblings the first time the set changes.
How that looks per target is in the idiom files; names are in
[naming.md](../../iac-rendering/references/naming.md).

## 2. Network exposure

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

## 3. Identity over keys

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

## 4. Encryption

Platform-managed keys are the default, and that is not a compromise — they are encrypted,
rotated and free, and the operational burden of customer-managed keys is real.

Customer-managed keys are warranted when a compliance regime names them, or when key
revocation needs to be a capability you actually hold. Choosing them pulls in a Key Vault
with purge protection, an identity with wrap/unwrap, and a rotation story. If the spec
asks for CMK without those, the answer is incomplete rather than ready.

Encryption in transit is never negotiable: TLS 1.2 as the floor, HTTPS-only where the
resource has the switch.

## 5. Diagnostics

Every resource routes diagnostics somewhere. A resource with no diagnostic setting is
invisible exactly when someone needs to see it.

- **Destination**: a Log Analytics workspace by default. A storage account only for
  long-retention archival, and then alongside the workspace, not instead of it.
- **Categories**: audit categories always. `allLogs` in non-production and for anything
  handling regulated data; be deliberate in production where volume has a price.
- **Metrics**: `AllMetrics`, which is cheap.

The workspace is shared infrastructure, like DNS zones — referenced, not created, by a
resource skill.

## 6. Exceptions

A guardrail that cannot be departed from gets worked around instead of discussed, which is
worse. So exceptions are allowed, and the cost is recording them:

- The spec records the value with `source: overridden` and a comment stating the reason.
- Generated code carries a comment at the departing attribute pointing at that reason.
- In `production`, the exception is confirmed explicitly during the interview rather than
  applied from a previous spec.

What is not allowed is a silent exception. If a generated resource departs from these rules
and nothing says why, that is the defect — not the departure.

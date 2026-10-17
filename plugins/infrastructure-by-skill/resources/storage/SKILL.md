---
name: storage
description: Author Azure storage resources as Terraform or Bicep by resolving their decisions — storage accounts, blob containers, file shares, queues. Use whenever a storage account, blob storage, an ADLS Gen2 / data lake account or a file share is to be created, changed or reviewed in infrastructure code, or re-rendered for the other IaC target.
---

# Azure storage

A resource family. The decisions live in per-resource question sets under
[questions/](questions/); this file routes to the right one and holds what is true across
the family.

## Pick the question set

| Request mentions | Question set | Notes |
|---|---|---|
| storage account, blob storage, ADLS Gen2, data lake, static website | `questions/storage-account.yaml` | [notes](references/storage-account/notes.md) |
| container, blob container | *not yet written* | A child of an account; ask whether the account exists |
| file share, Azure Files, SMB share | *not yet written* | Needs an account with the right kind |
| queue, storage queue | *not yet written* | Not Service Bus — check which the user means |

When a question set does not exist yet, say so rather than improvising one. Generating a
resource without its decision set is how this plugin loses the property that makes it worth
using. Fall back to
[the guardrails](../../core/iac-authoring/references/guardrails.md), generate from those
rules, and record in the spec that no question set backed it.

## Then

1. [iac-authoring](../../core/iac-authoring/SKILL.md) — the interview protocol: resolution
   order, what gets asked, the spec, and
   [references/guardrails.md](../../core/iac-authoring/references/guardrails.md) for where
   the defaults come from
2. [iac-rendering](../../core/iac-rendering/SKILL.md) — the spec into Terraform or Bicep,
   plus `references/<resource>/terraform.md` or `.../bicep.md` for this resource's
   specifics, and the validate step at the end of each idiom file

## True for the whole family

**The portal defaults are permissive and the guardrail defaults are not.** Public network
access, shared-key auth and anonymous blob access all ship enabled on a storage account.
The question sets invert all three. Expect that to surprise someone who has only created
accounts in the portal — say what you changed rather than letting them discover it.

**Data-plane objects are a separate decision from the account.** A container, share or
queue inherits the account's network posture and auth model and cannot soften it. If a
request mixes both — "ein Storage Account mit einem Container für Uploads" — resolve the
account first, then the child, and keep them in separate files so the account's lifecycle
is not tied to a container's.

**Nothing here creates shared infrastructure.** Private DNS zones, the Log Analytics
workspace and the resource group are referenced, never created. Two resource skills each
creating `privatelink.blob.core.windows.net` is a conflict that only surfaces at apply
time, which is why a pattern skill or the platform owns them.

## Naming

Storage account names are the awkward case in the whole CAF convention: globally unique,
3–24 characters, lowercase alphanumeric only. No hyphens — which is why a rendered account
name has none while a vnet's does. The Terraform provider handles that; in Bicep the
template assembles the name from vars and the length is the author's to check.

| Target | What the question set declares |
|---|---|
| Terraform | `naming.terraform` — `Azure::Microsoft.Storage/storageAccounts` |
| Bicep | `naming.abbreviation` — `st`, rendered into a var (see [naming.md](../../core/iac-rendering/references/naming.md)) |

Use those rather than constructing either yourself. The Bicep naming modules
(`utility/naming`, `genName`) are not ready to ship — never import them.

## Adding a resource to this family

1. Write `questions/<resource>.yaml` — see
   [question-set-format](../../core/iac-authoring/references/question-set-format.md)
2. Write `references/<resource>/notes.md` for what the question set cannot express:
   decisions fixed at creation, dependency order, the pitfalls worth naming
3. Write `references/<resource>/terraform.md` and `references/<resource>/bicep.md`
4. Add a row to the routing table above

Do **not** add a new skill for it. The skill listing has a shared character budget and
every extra entry spends it; the family is the triggering unit, the question set is the
knowledge unit. Keep this skill's `description` naming the family, not every resource in
it.

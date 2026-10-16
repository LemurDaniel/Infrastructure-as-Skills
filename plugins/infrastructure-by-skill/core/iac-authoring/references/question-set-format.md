# The question set format

One file per resource, at `questions/<resource>.yaml` inside its family skill. These files
are the actual content of this plugin — a family's `SKILL.md` is a router and a handful of
family-wide truths.

## Shape

```yaml
schema_version: 1

resource: Microsoft.Storage/storageAccounts
title: Azure Storage Account

# Both identifier forms, because the two targets spell them differently.
naming:
  terraform: "Azure::Microsoft.Storage/storageAccounts"
  bicep: "Microsoft.Storage/storageAccounts"

# What this resource cannot do, so the skill can hand off instead of improvising.
boundaries:
  - "Does not create the resource group; expects one (see placement.resource_group)."
  - "Private DNS zones are shared infrastructure — a pattern skill owns them."

groups:
  - id: placement
    title: Placement
    questions:
      - id: environment
        ask: Which environment is this for?
        type: enum
        values: [development, test, acceptance, production]
        required: true
        why: >
          Drives the rendered name, the tags, and the strictness of several
          defaults below. Nothing sensible can be guessed here.
        renders: naming parameter `environment`, tag `environment`

      - id: replication
        ask: Which replication does the data need?
        type: enum
        values: [LRS, ZRS, GRS, GZRS]
        default: ZRS
        confirm_in: [production]
        why: >
          ZRS survives a zone loss at roughly LRS cost and is the right floor for
          anything that is not scratch data. GRS only pays off with a documented
          cross-region recovery plan — without one it is cost for a capability
          nobody will exercise.
        renders: azurerm_storage_account.account_replication_type / sku.name
```

## Question fields

| Field | Required | Meaning |
|---|---|---|
| `id` | yes | Stable key. Referenced by pattern pre-answers and written to `infra-answers.yaml`. Renaming one breaks existing answer files, so treat it as an interface. |
| `ask` | yes | The question as a human would put it. Not the attribute name. |
| `type` | yes | `enum`, `bool`, `string`, `int`, `list`, `ref` |
| `values` | for `enum` | Allowed values. |
| `default` | no | The opinionated value. Its presence is what makes the question not get asked. |
| `required` | no | `true` means no default exists and it must be asked. Mutually exclusive with `default`. |
| `confirm_in` | no | Environments where the default is surfaced for confirmation rather than applied silently. |
| `why` | yes | The reasoning. This is what a reviewer reads and what justifies the default. |
| `renders` | yes | Which attribute(s) the answer drives, per target where they differ. Lets a review skill map code back to a decision. |
| `depends_on` | no | `{ question: <id>, equals: <value> }` — skip unless the condition holds. |
| `ref` | for `ref` | What the value points at, e.g. `subnet`, `log_analytics_workspace`. Signals that a pattern usually supplies it. |

## Rules that matter

**Default to the secure value, not the portal default.** They diverge, routinely and in
the same direction. `public_network_access` and `shared_access_key_enabled` are the classic
pair: Azure ships them permissive, and inheriting that as a baseline means every resource
this plugin generates starts from the wrong end.

**`why` is not decoration.** It is the only artefact that survives into review. "Secure
default" is not a `why`; the `why` is what breaks if the other value is chosen, or what it
costs. If you cannot write one, the question probably does not belong in the set.

**Keep `required` scarce.** Every required question is paid on every run forever. In
practice a resource has two or three genuinely un-guessable decisions — environment,
region, and what it connects to. The rest can default.

**Group order is review order.** placement → networking → identity → security →
data_protection → observability. Keep it, because a reviewer reading three different
resource skills should not have to relearn the layout each time.

**`depends_on` instead of asking dead questions.** Firewall rules are meaningless when
public access is disabled. Gate them rather than asking and discarding.

## Validate

```powershell
pwsh -NoProfile -File scripts/Test-QuestionSet.ps1 <family-directory>
```

Checks every `questions/*.yaml` in the family for the structural invariants: unique ids,
`required` and `default` not both set, enum defaults within `values`, `depends_on` pointing
at a question that exists, `why` and `renders` present, both naming forms declared, the
Bicep identifier not carrying an `Azure::` prefix, and every resource reachable from the
family skill's routing table.

# The question set format

One file per resource, at `resources/<family>/<resource>/questions.yaml` — beside the
resource's `notes.md`, `terraform.md` and `bicep.md`. These files are the actual content of
this plugin; a family's `routing.md` is a router and a handful of family-wide truths.

## Two scopes

| Scope | Where | Answers |
|---|---|---|
| `resource` (default) | `resources/<family>/<resource>/questions.yaml` | One resource's decisions |
| `deployment` | [`core/iac-authoring/questions/deployment.yaml`](../questions/deployment.yaml) | What holds for everything in one deployment |

The deployment set is resolved **first**, and a resource question that would re-ask one of
its decisions declares `from_deployment: <id>` instead of a default. Posture is one
decision per system, not one per resource — asking "should this be reachable from the
internet?" eight times in one run is the failure this prevents, and so is answering it
differently the eighth time.

A deployment set names no resource, so it carries no `resource:` and no `naming:` block,
and the consistency script exempts it from those checks. Everything else — groups, ids,
`why`, `renders`, `depends_on` — is identical.

## Shape

```yaml
schema_version: 1

resource: Microsoft.Storage/storageAccounts
title: Azure Storage Account

# Both identifier forms, because the two targets spell them differently, plus the
# abbreviation the Bicep side renders into a var (the naming modules are not shipped).
naming:
  terraform: "Azure::Microsoft.Storage/storageAccounts"
  bicep: "Microsoft.Storage/storageAccounts"
  abbreviation: "st"

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
        values: [development, test, qa, uat, integration, staging, preproduction, production, sandbox, demo, hotfix]
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
| `depends_on` | no | `{ question: <id>, equals: <value> }`, or `not_equals` — skip unless the condition holds. |
| `ref` | for `ref` | What the value points at, e.g. `subnet`, `log_analytics_workspace`. Signals that a pattern usually supplies it. |
| `from_deployment` | no | The deployment-set question whose answer this one takes. Mutually exclusive with `default` and `required`. |
| `forced_when` | no | Which answer elsewhere removes a value from `values`, or determines this one. Prose, because the conditions are not uniform enough to encode. Recorded as `forced` with `forced_by` in the spec. |
| `from_context` | no | The value comes from the spec's `context:` rather than being asked per resource. |

## Rules that matter

**Default to the secure value, not the portal default.** They diverge, routinely and in
the same direction. `public_network_access` and `shared_access_key_enabled` are the classic
pair: Azure ships them permissive, and inheriting that as a baseline means every resource
this plugin generates starts from the wrong end.

**A decision that holds for more than one resource belongs in the deployment set.** The
test is whether two resources could sensibly answer it differently. Posture, network
ownership, key protection and the diagnostics destination fail that test — they are one
answer per system. Replication, access tier and soft-delete windows pass it, and stay with
the resource.

**One answer may force another.** `key_protection: hsm` is not a flag; it requires Key
Vault Premium, and a software key cannot be converted in place later. Where that happens,
the forced value is pre-answered rather than asked, and the question that forced it is
named in the spec. A question whose answer is already determined is noise, but a *silently*
determined one is worse — say which mandate drove it.

**`why` is not decoration.** It is the only artefact that survives into review. "Secure
default" is not a `why`; the `why` is what breaks if the other value is chosen, or what it
costs. If you cannot write one, the question probably does not belong in the set.

**Keep `required` scarce.** Every required question is paid on every run forever. In
practice a resource has two or three genuinely un-guessable decisions — environment,
region, and what it connects to. The rest can default.

**Group order is review order.** placement → networking → identity → security →
data_protection → observability. Keep it, because a reviewer reading three different
resources should not have to relearn the layout each time.

**`depends_on` instead of asking dead questions.** Firewall rules are meaningless when
public access is disabled. Gate them rather than asking and discarding.

## Validate

Today: the repo's `.claude/skills/git-commit-conventions/scripts/Test-RepoConsistency.ps1`,
which checks naming forms, unique ids, `required`/`default` not combined, `why`/`renders`
present and routing reachability. The dedicated script below is **planned, not written**:

```powershell
pwsh -NoProfile -File scripts/Test-QuestionSet.ps1 <family-directory>
```

It would check every resource's `questions.yaml` in the family for the structural invariants: unique ids,
`required` and `default` not both set, enum defaults within `values`, `depends_on` pointing
at a question that exists, `why` and `renders` present, both naming forms and the
abbreviation declared, the Bicep identifier not carrying an `Azure::` prefix, and every
resource reachable from the family's outing.md.

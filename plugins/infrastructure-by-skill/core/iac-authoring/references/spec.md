# `infra-spec.yaml` — the handover interface

The interview does not produce code. It produces a **spec**, and the spec is what a backend
renders. Keeping that boundary sharp is the most load-bearing decision in this design.

## Why a spec and not direct generation

Three things fall out of it that direct generation cannot give you:

**It is the contract between backends.** The same spec can be rendered as Terraform, as
Bicep, or handed to `Infrastructure-as-Skills` for API-driven execution. Without a spec in
the middle, each backend grows its own private notion of what was decided, and there is
nothing to compare. With one, sending a single spec through two backends and diffing the
result is a test you can actually run — which is exactly the measurement that tells you
whether the research track is maturing.

**It is reviewable at the level decisions are made.** HCL records the *result* of a
decision and never the decision itself. `public_network_access_enabled = false` tells you
the value and nothing about whether anyone chose it. That gap is where infrastructure
review turns into archaeology.

**It makes regeneration a diff.** Re-running against an existing spec normally asks
nothing and changes nothing, so the diff shows precisely what moved — rather than a
rewrite nobody can audit.

## Shape

```yaml
schema_version: 1

spec:
  id: payments-api-prod
  target: terraform          # terraform | bicep | api  (api => Infrastructure-as-Skills)
  generated_by: infrastructure-by-skill
  skill: private-webapp
  skill_version: 0.1.0
  at: 2026-10-17T09:14:00Z

# Values every resource inherits. Resolved once, not per resource.
context:
  environment: production
  location: westeurope
  workload: payments
  subscription_id: 00000000-0000-0000-0000-000000000000
  resource_group_name: rg-we-prod-payments-01

# Present only when a pattern drove the run.
pattern:
  id: private-webapp
  resources: [app-service, storage-account, key-vault]

resources:
  storage-account:
    networking:
      public_network_access:
        value: disabled
        source: pattern
      private_endpoint_subnet:
        value: snet-data-prod-01
        source: asked
    security:
      shared_access_key_enabled:
        value: false
        source: pattern
      min_tls_version:
        value: TLS1_2
        source: default
    data_protection:
      blob_soft_delete_days:
        value: 7
        source: default

# Decisions that belong to no single resource. The pattern owns these.
wiring:
  private_dns_zones:
    value: [privatelink.blob.core.windows.net, privatelink.vaultcore.azure.net]
    source: pattern
  role_assignments:
    value:
      - from: app-service
        to: storage-account
        role: Storage Blob Data Contributor
    source: pattern
```

## `source` is what makes it a spec rather than a settings dump

Every value carries where it came from. Strip that field and the file degrades into a
config file whose provenance has to be guessed.

| `source` | Meaning |
|---|---|
| `stated` | The user said it in their request, before being asked |
| `asked` | The user answered it in the interview |
| `pattern` | A pattern skill pre-answered it |
| `default` | The question set's opinionated default applied |
| `carried` | Taken unchanged from a previous spec |
| `overridden` | The user contradicted a pattern pre-answer or a previous value |

`overridden` carries a comment on the same key saying what it departed from. It is the one
source that marks a deliberate exception, and an undocumented exception reads as an
accident a year later.

## Backend-neutral on purpose

The spec names **decisions**, not attributes. `public_network_access: disabled`, never
`public_network_access_enabled: false` — the latter is already Terraform's spelling for the
`azurerm` provider and would leak one backend's vocabulary into the interface the other
backends have to read.

The mapping from a decision to an attribute lives in the question set's `renders` field and
in each target's rendering reference. That is the layer allowed to know about
`networkAcls.defaultAction` versus `public_network_access_enabled`.

Target-specific escape hatches do exist, and are quarantined:

```yaml
resources:
  storage-account:
    _target_overrides:
      terraform:
        # Needed until azurerm supports it as a first-class argument.
        lifecycle_ignore: [tags["created_at"]]
```

Anything under `_target_overrides` needs a comment saying why, and a spec that accumulates
them is telling you the question set is missing a question.

## Reading one back

When a spec already exists in the target directory, load it before interviewing. Its values
enter resolution as `carried`, so a re-run normally asks nothing.

Two cases need care:

- **A question was added to the set since.** It is absent, resolves from its default, and
  is recorded as `default`. Name the additions rather than slipping them in.
- **`schema_version` is older than the question set's.** Say what changed before
  regenerating. Silently migrating a file whose purpose is auditability defeats the file.

## Validate

```powershell
pwsh -NoProfile -File scripts/Test-Spec.ps1 <path-to-infra-spec.yaml>
```

Checks that every value carries a known `source`, that referenced skills exist, that enum
values are within the question set's `values`, that no `required` question is missing or
defaulted, and that no decision key uses a backend's attribute spelling.

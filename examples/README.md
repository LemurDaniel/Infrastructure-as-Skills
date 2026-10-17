# Examples

What good looks like, end to end: a request, the spec the interview wrote from it, and the
code rendered from the spec. Point at these rather than describing the shape — a
question-set author sees what a decision becomes, a renderer sees the file split and the
idiom, a reviewer sees what `source:` buys.

| Example | Targets | Scenario | Why it is here |
|---|---|---|---|
| [`private-storage-on-platform/`](private-storage-on-platform/) | Terraform, Bicep | One storage account, production, behind a referenced hub and workspace, BSI C5 | The straightforward case: every platform part is referenced, one resource, `granularity: single`. Rendered to both targets from the one spec, so the two can be diffed. **Authored render** — it predates the AVM-first rule and stands for `implementation: authored` until re-rendered |

Planned: the same spec re-rendered on the AVM modules (the primary path since the
rendering references moved to it — each resource's `terraform.md` / `bicep.md` carries the
call), and `greenfield-telemetry` — three resources, created network and workspace, the
harder case.

## What each directory holds

```
<case>/
  request.md            # the user's words, verbatim
  infra-spec.yaml       # the interview's output - the artefact everything else follows from
  naming.yaml           # the convention, a full copy of naming.default.yaml
  *.tf, *.tfvars        # the Terraform render, one concern per file
  tests/*.tftest.hcl    # plan-only, platform mocked, naming provider real - one
                        # assert per spec decision, checked by Test-RenderCoverage.ps1
  bicep/main.bicep      # the Bicep render of the same spec
  bicep/main.bicepparam # its parameters - the same values as terraform.tfvars
```

## Running one

```powershell
cd examples/private-storage-on-platform
terraform init
terraform fmt -check -recursive
terraform validate
terraform test
pwsh -NoProfile -File ../../plugins/infrastructure-as-skills/core/iac-rendering/scripts/Test-RenderCoverage.ps1 ./infra-spec.yaml

bicep build --stdout bicep/main.bicep > $null
bicep build-params bicep/main.bicepparam --stdout > $null
bicep lint bicep/main.bicep
```

Needs the `hashicorp/azurerm` and `LemurDaniel/naming` providers from the registry, and
the Bicep CLI. No credentials: the tests mock `azurerm`, and nothing plans or what-ifs
against a subscription. The lock file is not committed, so `init` resolves the current
`~> 5.0` / `~> 1.0` — if a render stops validating after a provider release, that is a
finding for the rendering reference, not for the example.

## The cross-backend diff

The spec design promises that one spec rendered twice differs only where the platforms
genuinely differ. `private-storage-on-platform` is the first measurement. Every decision
in the spec lands in both renders with the same value; what differs:

| | Terraform | Bicep | Verdict |
|---|---|---|---|
| Private endpoint name | `pep-we-prod-invoicing-blob-01` via the provider's `subname` parameter | same, assembled from vars | **Was a divergence**: the first Terraform render appended `-blob` after the index. Fixed in `terraform.md` |
| `network_rules` / `networkAcls` with public access off | omitted — the ACL has nothing to filter and a second resource could fight it | present — documents the posture, nothing to conflict with | Genuine, and each reference says why |
| Role assignments | `role_definition_name` string, optional container `scope` | union-typed `role`, GUID map, account scope | Genuine: Bicep has no name lookup without a registry module |
| Diagnostics | two settings, account + `blobServices/default` | two settings, `scope:` on the nested resource | Same |
| Soft delete, versioning | `blob_properties` on the account | nested `blobServices/default` resource | Same decision, different shape — documented in `bicep.md` |
| Per-endpoint output | map keyed by sub-resource, private IP | array of `{subresource, id}` | Bicep cannot index a resource loop inside a lambda (BCP247) |
| Naming inputs | the provider reads `naming.yaml` at plan time | `locationCodes` holds only the regions the deployment uses | Inherent: a new region is a regenerated var block, see `naming.md` |
| Provider-level | `storage_use_azuread = true` | — | Inherent: no provider in Bicep; `az` authenticates with Entra ID anyway |
| Subscription | `var.subscription_id` on the provider | the deployment's scope on the command line | Inherent |
| Soft delete of the workspace, deletion locks | `features {}` | — | Not applicable here |

## Rules

- An example is **rendered, never applied**. Subscription ids and names are placeholders.
- An example is regenerated from its spec when a rendering reference changes, and the diff
  is the review. Hand-editing the `.tf` or `.bicep` without touching the reference is how
  the two drift.
- `request.md` is the eval prompt verbatim where the example comes from a case; the spec
  must satisfy that case's graders.
- A new divergence between the two renders of one spec is a finding for a rendering
  reference, never something to patch in one example.

# Examples

What good looks like, end to end: a request, the spec the interview wrote from it, and the
code rendered from the spec. Point at these rather than describing the shape — a
question-set author sees what a decision becomes, a renderer sees the file split and the
idiom, a reviewer sees what `source:` buys.

| Example | Targets | Scenario | Why it is here |
|---|---|---|---|
| [`private-storage-on-platform/`](private-storage-on-platform/) | Terraform, Bicep | One storage account, production, behind a referenced hub and workspace, BSI C5 | The straightforward case: every platform part is referenced, one resource, `granularity: single`. Rendered to both targets from the one spec on the **Azure Verified Modules** (`avm-res-storage-storageaccount` v0.10.0, `avm/res/storage/storage-account` 0.33.1, resolved 2026-10-18), so the two can be diffed. The git history before that date holds the authored render of the same spec |
| [`greenfield-telemetry/`](greenfield-telemetry/) | Bicep | Three resources, staging, nothing referenced: own network with two subnets, own workspace, private storage, `landing_zone: standalone` | The `create` branches the first example never reaches, including the privatelink zone the deployment owns and links. Four AVM modules in one root, the wiring between them in the root. The first render with tests against the compiled ARM, and the first spec carrying `source: requirement` |


## What each directory holds

```
<case>/
  request.md            # the user's words, verbatim
  infra-spec.yaml       # the interview's output - the artefact everything else follows from
  naming.yaml           # the convention, a full copy of naming.default.yaml
  platform.yaml         # the platform profile the platform team would have written
  *.tf, *.tfvars        # the Terraform render, one concern per file
  tests/*.tftest.hcl    # plan-only, platform mocked, naming provider real - one
                        # assert per spec decision, checked by check_render_coverage.py
  tests/*.armtest.yaml  # the Bicep tests: one entry per decision against the compiled
                        # ARM, run by run_arm_tests.py, counted by the same coverage check
  bicep/main.bicep      # the Bicep render of the same spec
  bicep/main.bicepparam # its parameters - the same values as terraform.tfvars
  bicep/bicepconfig.json # symbolicNameCodegen on, so the tests can address resources by name
```

## Running one

```powershell
cd examples/private-storage-on-platform
terraform init
terraform fmt -check -recursive
terraform validate
terraform test
python3 ../../plugins/infrastructure-as-skills/core/iac-rendering/scripts/check_render_coverage.py ./infra-spec.yaml

bicep build --stdout bicep/main.bicep > $null
bicep build-params bicep/main.bicepparam --stdout > $null
bicep lint bicep/main.bicep

cd ../greenfield-telemetry
bicep build --stdout bicep/main.bicep > $null && bicep lint bicep/main.bicep
python3 ../../plugins/infrastructure-as-skills/core/iac-rendering/scripts/run_arm_tests.py ./infra-spec.yaml
python3 ../../plugins/infrastructure-as-skills/core/iac-rendering/scripts/check_render_coverage.py ./infra-spec.yaml
```

Needs the AVM module and the `azurerm`, `azapi`, `modtm`, `random` and
`LemurDaniel/naming` providers from the registry, and the Bicep CLI, which resolves the
module from `mcr.microsoft.com`. No credentials: the tests mock `azurerm`, `azapi` and
`modtm`, and nothing plans or what-ifs against a subscription. The lock file is not
committed, so `init` resolves the current `~> 0.10.0` / `~> 5.0` / `~> 2.11` / `~> 1.0` —
if a render stops validating after a release, that is a finding for the rendering
reference, not for the example.

## The cross-backend diff

The spec design promises that one spec rendered twice differs only where the platforms
genuinely differ. `private-storage-on-platform` is the measurement, taken twice: on the
authored render (2026-10-17) and again on the AVM render (2026-10-18). Every decision in
the spec lands in both renders with the same value; what differs:

| | Terraform | Bicep | Verdict |
|---|---|---|---|
| Private endpoint name | `pep-we-prod-invoicing-blob-01` via the provider's `subname` parameter | same, assembled from vars | **Was a divergence** in the authored render: Terraform appended `-blob` after the index. Fixed in `terraform.md` |
| `network_rules` / `networkAcls` with public access off | present, `Deny` + `AzureServices` — the module renders it into the body either way | present | **Was a divergence** (omitted on the Terraform side); the module removed it, and the bypass became testable |
| Role assignments | `role_definition_id_or_name` by name | `roleDefinitionIdOrName` by name, union-typed `role` param | **Was a divergence** (a GUID map on the Bicep side); the module's shared interface removed it |
| Diagnostics | `diagnostic_settings_storage_account` + `diagnostic_settings_blob` inputs | `diagnosticSettings` + `blobServices.diagnosticSettings` params | Same: the module knows the account emits metrics only |
| Soft delete, versioning | `blob_properties` input, nested objects | `blobServices` param, flat `…Enabled` / `…Days` pairs | Same decision, different shape — documented in each reference |
| Per-endpoint output | map keyed by sub-resource from the module's `private_endpoints` output | the module's `privateEndpoints` array | Shape of each module's output |
| Naming inputs | the provider reads `naming.yaml` at plan time | `locationCodes` holds only the regions the deployment uses | Inherent: a new region is a regenerated var block, see `naming.md` |
| Provider-level | `storage_use_azuread = true`; `azapi`, `modtm`, `random` declared for the module | — | Inherent: no provider in Bicep; `az` authenticates with Entra ID anyway |
| Subscription, resource group | `var.subscription_id` on both providers; the group read by `data` and passed as `parent_id` | the deployment's scope on the command line | Inherent |
| Telemetry | `enable_telemetry = true` | `enableTelemetry: true` | Same, written on both calls |

Two of the three genuine divergences the authored render had were the module's doing:
the modules implement the same interface on both sides, which is the argument for AVM
first, measured.

## Rules

- An example is **rendered, never applied**. Subscription ids and names are placeholders.
- An example is regenerated from its spec when a rendering reference changes, and the diff
  is the review. Hand-editing the `.tf` or `.bicep` without touching the reference is how
  the two drift.
- `request.md` is the eval prompt verbatim where the example comes from a case; the spec
  must satisfy that case's graders.
- A new divergence between the two renders of one spec is a finding for a rendering
  reference, never something to patch in one example.

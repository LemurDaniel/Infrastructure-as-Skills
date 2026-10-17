# Examples

What good looks like, end to end: a request, the spec the interview wrote from it, and the
code rendered from the spec. Point at these rather than describing the shape — a
question-set author sees what a decision becomes, a renderer sees the file split and the
idiom, a reviewer sees what `source:` buys.

| Example | Target | Scenario | Why it is here |
|---|---|---|---|
| [`private-storage-on-platform/`](private-storage-on-platform/) | Terraform | One storage account, production, behind a referenced hub and workspace, BSI C5 | The straightforward case: every platform part is referenced, one resource, `granularity: single` |

Planned: `greenfield-telemetry` in Bicep — three resources, created network and workspace,
the harder case — and the same spec through both targets for the cross-backend diff.

## What each directory holds

```
<case>/
  request.md          # the user's words, verbatim
  infra-spec.yaml     # the interview's output - the artefact everything else follows from
  naming.yaml         # the convention, a full copy of naming.default.yaml
  *.tf, *.tfvars      # the render, one concern per file
  tests/*.tftest.hcl  # plan-only, platform mocked, naming provider real
```

## Running one

```powershell
cd examples/private-storage-on-platform
terraform init
terraform fmt -check -recursive
terraform validate
terraform test
```

Needs the `hashicorp/azurerm` and `LemurDaniel/naming` providers from the registry. No
credentials: the tests mock `azurerm` and never plan against a subscription. The lock file
is not committed, so `init` resolves the current `~> 5.0` / `~> 1.0` — if a render stops
validating after a provider release, that is a finding for the rendering reference, not
for the example.

## Rules

- An example is **rendered, never applied**. Subscription ids and names are placeholders.
- An example is regenerated from its spec when a rendering reference changes, and the diff
  is the review. Hand-editing the `.tf` without touching the reference is how the two drift.
- `request.md` is the eval prompt verbatim where the example comes from a case; the spec
  must satisfy that case's graders.

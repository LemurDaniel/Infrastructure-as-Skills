---
name: iac-plan-review
description: Validate Azure infrastructure code and explain what it will actually do — terraform validate/plan, Bicep build and what-if, Checkov or OPA, then which changes are service-affecting and which are noise. Use after generating any Terraform or Bicep, and whenever asked to check, lint, plan, dry-run or risk-assess infrastructure code, or whether a change is safe to apply.
---

# Reviewing an infrastructure plan

Syntactically valid code is not reviewed code. This skill is the gate between "it compiles"
and "we know what it does".

## The sequence

Run it in order; each step is cheap relative to the one after it, so there is no reason to
discover a formatting problem during a `what-if`.

### Terraform

```bash
terraform fmt -recursive -check    # drop -check to fix in place
terraform init -backend=false      # enough for validate; no state access
terraform validate
terraform plan -out=tfplan
terraform show -json tfplan > tfplan.json
```

`-backend=false` matters: `validate` needs the providers, not the state, and initialising
a real backend to check syntax is how a read-only review acquires a state lock.

### Bicep

```bash
bicep build --stdout main.bicep    # unknown properties fail here
bicep lint main.bicep
az deployment group what-if \
  --resource-group <rg> \
  --template-file main.bicep \
  --parameters main.bicepparam
```

`what-if` is the only step that compares against what is deployed. It needs credentials and
reader on the resource group, and it changes nothing.

## Policy scanning

Structural checks catch what a plan cannot: that a correct-looking change is against the
rules.

```bash
# Terraform, against the plan rather than the source — catches computed values
checkov -f tfplan.json --framework terraform_plan

# Bicep, via the compiled ARM template
bicep build --outfile main.json main.bicep && checkov -f main.json --framework arm

# Custom rules, where the repo has them
conftest test tfplan.json --policy policy/
```

Scan the **plan**, not the source. A source scan cannot see a value that comes from a
variable, a data source or a module output, which is where the interesting violations hide.

Expect noise. A Checkov run on real infrastructure produces findings that are wrong for the
context, and treating every one as a defect trains people to ignore the tool. Triage them:
a finding that contradicts a recorded `overridden` decision in `infra-spec.yaml` is
answered, not open.

## Explaining the plan

This is the part that cannot be automated, and the reason this skill exists rather than a
shell alias.

A plan is a list of attribute diffs. What a reviewer needs is which diffs matter. Structure
the explanation as:

**1. What is being created, changed, destroyed** — counts, then the resources by name. If
nothing is destroyed, say so explicitly; it is the first thing anyone wants to know.

**2. Replacements, called out separately.** A `-/+` is not a change, it is a delete and a
create, and for a stateful resource that is data loss. Name the attribute that forces it:

```
REPLACED  azurerm_storage_account.this
          forced by: account_replication_type  ZRS -> GZRS
          A storage account cannot change replication in place. The account is
          destroyed and recreated; existing blobs are not migrated.
```

Replacements are the single most common way generated infrastructure causes an outage. If a
plan contains one, lead with it.

**3. Service-affecting changes.** Changes that interrupt traffic even without a
replacement: a network ACL that starts denying, `public_network_access` flipping to
disabled while a consumer is still off-network, a TLS floor rising above what a client
supports, local auth being disabled while a connection string is still in use somewhere.

This is where the spec earns its place. A change to `shared_access_key_enabled` is a
one-line diff and potentially a broken application — and the question set's `why` field
already says what that switch is for.

**4. Noise.** Tag changes, drifted `last_modified` attributes, reordered sets. Name them as
a group and move on, so the signal above is not buried.

**5. What the plan cannot see.** Data not migrated, a DNS record that must exist before the
private endpoint resolves, a role assignment that takes minutes to propagate, a consumer
that needs its connection string swapped for a managed identity. The plan has no opinion on
any of it and it is where real rollouts fail.

## Risk assessment

Close with a judgement, not a hedge. Three outcomes:

- **Safe to apply** — additive, or changes nothing a consumer depends on.
- **Apply with a window** — service-affecting but reversible, or needs a consumer change
  first. Say what the window needs to cover and in what order.
- **Do not apply yet** — a replacement of a stateful resource with no migration, or a
  destroy nobody asked for. Say what would make it safe.

Where the environment is `production`, say the environment out loud in the verdict. The
same diff carries a different risk in dev, and a reviewer skimming should not have to infer
which one they are looking at.

## Reviewing against the spec

When `infra-spec.yaml` is present, check the code against it and not just against the
rules:

- A guardrail violation that the spec records as `overridden` with a reason is answered.
- A decision in the spec that the code does not implement is a rendering bug — report it as
  one rather than as a policy finding.
- Code that departs from a guardrail with **nothing** in the spec about it is the real
  finding. See [azure-guardrails](../azure-guardrails/SKILL.md) for what the rules are and
  [references/spec.md](../iac-authoring/references/spec.md) for the `source` values.

## Never

- `terraform apply` as part of a review. Validation is read-only; applying is a separate
  instruction, and `plan`/`what-if` exist precisely so the two stay apart.
- `terraform init` against a real backend when only `validate` is needed — it takes a
  state lock a review has no business holding.
- Reporting "plan succeeded" as the result. A plan that succeeds and replaces the
  production database has succeeded.

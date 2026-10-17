---
name: iac-rendering
description: Turns an infra-spec.yaml into Terraform or Bicep — file and module layout, variables, naming, tagging, tests. Read when rendering a spec, when porting a configuration between the two targets, or when reviewing generated code for idiom.
---

# Rendering a spec

This skill is the second half of the pipeline:

```
question set  ──interview──>  infra-spec.yaml  ──render──>  Terraform / Bicep
              [iac-authoring]                  [here]
```

The split is the point. The interview resolves decisions and writes them in a
backend-neutral vocabulary; this layer is the only one allowed to know that
`public_network_access: disabled` is `public_network_access_enabled = false` in one target
and `properties.publicNetworkAccess: 'Disabled'` in the other. Merge the two and the
vocabulary leaks within a week.

So: **never render without a spec.** If there is none, go to
[iac-authoring](../iac-authoring/SKILL.md) and write one first. Rendering straight from a
conversation produces code nobody can regenerate and a decision record that does not exist.

## What the spec hands over

| Spec | What this layer does with it |
|---|---|
| `spec.target` | Picks Terraform or Bicep. Never both from one run |
| `composition` | The module split. One `modules` entry is a directory (Terraform) or a file (Bicep) |
| `context` | Variables/parameters shared by every module, resolved once |
| `resources.<id>` | Decisions → attributes, via the question set's `renders` and the resource's own rendering reference |
| `wiring` | Renders into the root, never into a module — only the caller sees both ends |
| `_target_overrides` | Target-specific escape hatches, each with its comment |

The schema is in
[../iac-authoring/references/spec.md](../iac-authoring/references/spec.md). Read it rather
than inferring the shape from an example spec.

## Order of work

1. **Match the repository before the defaults.** An existing layout, module granularity or
   API version wins over anything in the references here. Generated code that does not look
   like its neighbours gets rewritten by hand, and then the spec is stale.
2. **Read the target idiom** — [terraform-idiom](references/terraform-idiom.md) or
   [bicep-idiom](references/bicep-idiom.md), not both.
3. **Read the resource's own rendering reference**, `resources/<family>/references/<resource>/{terraform,bicep}.md`.
   It holds what the spec cannot: which decisions are fixed at creation, which live on a
   nested resource, the shape differences between the two targets.
4. **Render names from the right mechanism** — [naming.md](references/naming.md). The
   Terraform provider resolves them; in Bicep they are assembled from vars because the
   naming modules are not shipped.
5. **Write the secure value explicitly**, even where it matches the provider or API
   default. A default can move between versions and an absent attribute is invisible in
   review.
6. **Validate before handing over.** Syntactically valid is not done — `fmt` →
   `validate` → `plan` / `what-if`, then say which diffs are service-affecting. The
   commands are at the end of each idiom file.

## Do not invent attributes

A plausible-looking argument that does not exist is worse than asking. Provider schemas
move, and exact spellings are not something to recall from memory.

- **Terraform** — `terraform providers schema -json` in the target directory (needs
  `terraform init`). Narrow it with `jq`; it is megabytes.
- **Bicep** — compile early: `bicep build --stdout <file>` fails loudly on an unknown
  property. For API versions, prefer the one already used in the repository.

When neither is available, name the attribute you are unsure about instead of guessing. A
named uncertainty is cheap to resolve; a wrong argument found at apply time is not.

## Porting between the two targets

A spec rendered twice should differ only where the platforms genuinely differ. The
asymmetries that do not survive a naive port are called out in each idiom file — module
scope versus provider aliases, deployment names, where soft delete lives, how replication
is spelled. A port that reads as a transliteration has usually lost one of them.

## Reference files

| File | When |
|---|---|
| [references/naming.md](references/naming.md) | Always, before rendering a name |
| [references/terraform-idiom.md](references/terraform-idiom.md) | Target is Terraform |
| [references/bicep-idiom.md](references/bicep-idiom.md) | Target is Bicep |
| [../iac-authoring/references/spec.md](../iac-authoring/references/spec.md) | Reading the spec you render from |
| [../iac-authoring/references/guardrails.md](../iac-authoring/references/guardrails.md) | A value in the spec looks wrong and you need the rule behind it |

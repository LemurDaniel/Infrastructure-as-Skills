# Progress

The handoff between sessions. Read it at the start of one, rewrite it at the end of one —
the goal rarely changes, the rest does. Keep it tight: what is here is what the next
session starts from, and what is not here it re-derives.

## Goal

A Claude Code plugin that authors Azure infrastructure as Terraform or Bicep from an
interview, consistently: the same request produces the same decisions, every decision is
recorded with where it came from, and a backend renders from that record rather than from
the conversation.

## Decisions, and why

- **Question sets, not modules or templates.** The hard part of a resource is its
  decisions, not its syntax. Generic generation gets the syntax right and the decisions
  wrong.
- **Spec in the middle.** `infra-spec.yaml` is the handover; code is rendered from it. It
  makes two backends comparable and regeneration a diff.
- **One triggering skill, families as routing, question sets as knowledge.** The skill
  listing has a shared character budget and drops descriptions silently when it overflows.
  A skill per family overflowed at the sixth family.
- **Defaults from the guardrails, not the portal.** Portal defaults are permissive in the
  same direction every time; inheriting them is how exposure findings happen.
- **Landing-zone model.** A workload lands in an application landing zone; the platform
  (hub, DNS zones, central workspace) exists and is referenced, never built.
- **Rendering references target `azurerm` 5.x.** `public_network_access` is a string there;
  the 4.x bool is deprecated and `validate` does not warn.
- **Plan-only tests mock the platform.** A referenced vnet or workspace is a `data` block,
  which a plan reads from Azure; `mock_provider "azurerm"` with parseable ids keeps the
  test credential-free.
- **Sub-resource names go through `<?SUBNAME>`**, not appended to a finished name. The
  first cross-backend diff found the Terraform render naming a private endpoint
  `…-01-blob` while Bicep said `…-blob-01`; the convention has the token for exactly this.
- **No registry alias, no registry modules.** The Bicep render inlines diagnostics and role
  assignments when `bicepconfig.json` has no `br/modules`; inventing the alias bakes a
  PoC address into a consumer repository.

## Open

- `Test-QuestionSet.ps1` is referenced by the authoring docs and not written.
- `patterns/` is empty; composition is specified on paper only.
- No render has been applied: neither `terraform plan` nor `what-if` has run against a
  subscription, so the renders are validated, not proven.
- The eval suite has no committed baseline yet; the first full run writes it.
- Remaining families: `compute`, `data`, `security`.

## Next

Render `greenfield-telemetry` — three resources, created network and workspace, Bicep —
as the second example. It exercises the `create` branches (`azurerm_subnet` resource
instead of `data`, a workspace resource, `log_retention_days`) that the first example
never reached, and every one of those branches in the rendering references is untested.

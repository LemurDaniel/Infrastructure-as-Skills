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

## Open

- `Test-QuestionSet.ps1` is referenced by the authoring docs and not written.
- `patterns/` is empty; composition is specified on paper only.
- No spec has been rendered to Bicep, so the cross-backend diff has never run.
- No render has been applied against a subscription.
- The eval suite has no committed baseline yet; the first full run writes it.
- Remaining families: `compute`, `data`, `security`.

## Next

Render `private-storage-on-platform` to Bicep from the same spec and diff it against the
Terraform render in `examples/`. That is the measurement the spec design promises and the
one thing nothing here has tested.

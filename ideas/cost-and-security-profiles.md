# Cost estimate and optimisation profiles

**Status:** sketch

## Idea

Every spec gets a rough monthly cost estimate, per stage. On top of it, selectable profiles
that change which decisions are proposed:

- **cost first:** cheaper SKUs and replication, shorter retention, `non_production_default`
  applied wherever it is allowed.
- **security first:** private endpoints, no shared keys, longer retention, CMK where offered.
- **balanced:** the guardrail defaults as they are.

A profile only moves decisions that are not security-shaped in the cost direction (same
rule as `non_production_default`); the estimate shows what each switch costs or saves.

## Open questions

- Price source: Azure Retail Prices API (public, no auth) is the likely one.
- Where the profile lives: a `context` field in the spec, or a question in the deployment set?
- The estimate is an order of magnitude, not a quote; it says so.

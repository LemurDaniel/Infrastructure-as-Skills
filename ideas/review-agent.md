# Review agent for existing infrastructure

**Status:** sketch

## Idea

Point it at an existing Terraform or Bicep repo (later: a subscription). It reads what is
there, reconstructs an `infra-spec.yaml` from it (which decisions were taken, per resource),
and compares each decision with the guardrail default of the question set.

## Output

A findings list: decision, found value, guardrail default, why the default is what it is
(the question set already carries the reasoning), and a suggested fix. Optionally the
reconstructed spec, so the repo can be re-rendered later (a migration path onto AVM).

## Open questions

- Reading Bicep/Terraform into a spec: parse HCL/ARM, or let the model read and the spec
  check validate?
- Unknown resource types: reported as "no question set", never guessed.
- Pull request into the reviewed repo, or a report only?

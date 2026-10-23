# Spec versions and diff

**Status:** sketch

## Idea

The `infra-spec.yaml` is kept per version (in git next to the rendered code, or as a copy per
run of the scheduled agent). A diff of two versions is written as a readable decision list
instead of a YAML diff:

> storage.replication: LRS -> GRS (production only) - reason from the question set

## Output

A "what changed" section in `infra-decisions.md` (extension of `export_decisions.py`), and
the same text as the description of a pull request that changes a spec. The reader sees which
decisions moved and why, without reading Terraform or Bicep.

## Open questions

- Where the old version comes from: git history of the spec file, or an explicit snapshot
  written at each render?
- Reason for a change: taken from the question set, or asked of the person who changed it?
- Added or removed resources versus changed decisions: shown separately.

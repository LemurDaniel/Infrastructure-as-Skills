# AVM drift watch

**Status:** sketch

## Idea

The light version of the [autonomous agent](autonomous-terraform-agent.md): no apply, no test
subscription. On a schedule it looks up the current AVM versions (Bicep: MCR tag list;
Terraform: module repo tags), compares them with the pinned versions in the resource
references, reads the module README inputs for the new version and diffs them against the
inputs the references render.

## Output

A separate branch and a pull request in this repo that bumps the pin and lists what changed
(new, renamed or removed inputs, changed defaults, new provider requirements). Nothing
else is touched.

## Why

The `PROGRESS.md` todo, and a good first step: cheap, no Azure access needed, and its PR
mechanics are reused by the full agent.

## Open questions

- A GitHub Action on a cron, or the agent host from the main idea?
- How a changed default is flagged when it now matches or breaks a guardrail.

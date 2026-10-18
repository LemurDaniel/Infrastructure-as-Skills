# The second request

A follow-up to [request.md](request.md), run as an extension run on the spec that run
wrote: only the delta is asked and reported, the earlier decisions are carried.

> Der Code liegt in GitHub. Bitte mit GitHub Actions ausrollen.

That answers `deployment.deploy_mechanism` (`github`, `source: stated`). `pipeline_auth`
(`workload_identity`) and `pipeline_approvals` (`production`) take their defaults.

The development and test stages are still `open:` in the spec. The pipeline has all three
stage blocks anyway, and `environments/development.tfvars` and `test.tfvars` hold
placeholders (the all-zero GUID, `OPEN-<what>`): the scaffold stands. The first step of a
stage's plan job refuses a file that still holds one, so nothing deploys - production
included, which waits behind them - until the open items are answered and the placeholders
replaced. The render is `.github/workflows/`; the checks are in the README of the examples.

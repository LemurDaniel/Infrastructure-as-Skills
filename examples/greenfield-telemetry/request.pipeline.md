# The second request

A follow-up to [request.md](request.md), run as an extension run on the spec that run
wrote: only the delta is asked and reported, the earlier decisions are carried.

> Wir nutzen Azure DevOps für die Pipelines.

That answers `deployment.deploy_mechanism` (`azure_devops`, `source: stated`).
`pipeline_auth` (`workload_identity`) and `pipeline_approvals` (`production`) take their
defaults.

Only staging is resolved in the spec; development, test and production are `open:`. The
pipeline has all four stage blocks anyway, in the stack's order, and
`bicep/main.development.bicepparam`, `main.test.bicepparam` and `main.production.bicepparam`
hold `OPEN-...` placeholders: the scaffold stands. The first step of a stage's plan job
refuses a file that still holds one, so nothing deploys - staging included, which waits
behind development and test - until the open items are answered and the placeholders
replaced. The Bicep root is `bicep/`, so every pipeline step works in that directory. The
render is `azure-pipelines.yml` and `.azure-pipelines/stage.yml`; the checks are in the
README of the examples.

# The second request

A follow-up to [request.md](request.md), run as an extension run on the spec that run
wrote: only the delta is asked and reported, the earlier decisions are carried.

> Der Code liegt in GitLab. Bitte mit GitLab CI ausrollen.

That answers `deployment.deploy_mechanism` (`gitlab`, `source: stated`). `pipeline_auth`
(`workload_identity`) and `pipeline_approvals` (`production`) take their defaults.

This example is the storage example of `../private-storage-on-platform/` with a GitLab
pipeline instead of GitHub Actions - one spec cannot name two systems, and two pipelines
applying one state race for its lock. Development and test are `open:` in the spec, so
their stage files hold placeholders and the pipeline refuses them; production waits behind
them. The render is `.gitlab-ci.yml`.

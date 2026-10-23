# Autonomous Terraform agent

**Status:** sketch

## Idea

An agent that generates Terraform configurations from a request and tests them on its own,
against a real test subscription. It uses this plugin (question sets, AVM first, the
render-with-tests contract) as its knowledge, and applies what it renders to check that the
result actually deploys.

## Setup

- **Agent host:** an App Service running the agent, with its own Azure AI Foundry project
  (model deployment) in the test subscription.
- **Test subscription:** where the agent applies and destroys. Isolated from anything real.
- **Storage account:** holds the Terraform state (one key per run) and, per run, the
  generated configuration and the results, so every run can be traced afterwards.
- **Identity:** a managed identity on the App Service, with rights scoped to the test
  subscription (or a dedicated resource group scope) and to the storage account.

## Trigger

Scheduled, not on request. A timer (App Service WebJob, or a Logic App / Container Apps job
calling the App Service) starts a run; there is no human in the loop. Each run picks its
targets itself - question sets whose AVM version or provider changed since the last run
first, then the rest in rotation - and writes the verdict to the storage account.

## Run loop (first sketch)

1. Run starts on schedule -> pick a target, answer the interview from defaults or a stored
   spec (`infra-spec.yaml`).
2. Render Terraform plus tests from the spec.
3. `fmt`, `validate`, `terraform test` (plan-only), coverage check.
4. `plan` and `apply` in the test subscription; check the result against the spec.
5. `destroy`.
6. Upload config, plan, test output and a verdict to the storage account.
7. On a finding or an improvement (a changed default, a new AVM input, a failing test, a
   fixed reference): push a separate branch to this repo and open a pull request with the
   evidence (run id, plan, test output). Never commits to `master`; a human merges.

## Why it might be worth it

- Closes the gap the repo has today: renders are verified by plan-only tests with a mocked
  platform, never applied. An apply shows what AVM version drift, provider changes and
  policy actually do.
- Produces the evidence for the eval question "does the plugin beat plain generation" on
  real deployments, not just on graded files.
- Catches AVM drift (the todo in `PROGRESS.md`) as a by-product.

## Open questions

- Schedule: how often (nightly, weekly), and what one run covers - all question sets, or a
  rotating subset to keep cost down? A full run is the AVM drift check.
- Cost and cleanup: budget cap, tags with a TTL, a sweeper for runs that died before destroy.
- Guardrails for the agent: deny list (no role assignments outside scope, no other
  subscriptions), `terraform apply` only inside the run's own resource group.
- Resources that need a platform (hub network, DNS zones, policy): mocked as today, or a
  small standing platform in the test subscription?
- Where the agent logic lives: Claude Agent SDK app in the App Service, with the plugin
  mounted, vs. Foundry Agent Service calling out to a runner.
- Pull requests: one branch and PR per finding, or batched per run? A bot identity or a GitHub App with only `contents` and `pull-requests` on this repo; dedupe against open PRs so a run does not open the same one twice.
- Retention of state and results; whether results feed back into the repo (evals, notes).

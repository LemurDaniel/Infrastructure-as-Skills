# Container Registry - what the question set cannot express

## Fixed at creation

- **The name.** Global, 5-50 characters, alphanumeric only; it is the login server
  (`<name>.azurecr.io`) written into every image reference, so a rename is a re-tag of every
  consumer.
- **Zone redundancy of the home region.** Modifying it forces a new registry.
- **A customer-managed key.** Set at creation; a registry that loses the key serves nothing.
- **The home region.**

## Ordering

The identity and its role on the Key Vault key (for `customer_managed`), then the registry,
then its private endpoint, then the role assignments, then the first push, then the consumers
that pull. A consumer's pull role needs the consumer's identity, which exists only after the
consumer does: the puller is created with an identity first (user-assigned, or system-assigned
and the role granted straight after), and the image is pulled only once the role has
propagated - the cause of the usual `ImagePullBackOff` on a first deployment.

## Pitfalls

**A closed registry cannot be pushed to from outside the network.** With
`public_network_access: disabled` a pipeline runner outside the network cannot push. Either the
runner is inside, or the image is built by an ACR task, or the registry is opened for the
duration of the push - a decision for the pipeline, not for this set.

**Pull needs the role and the network and the name.** The puller needs `AcrPull`, a route to the
registry (private endpoint or an allowed address) and the DNS record for the login server *and*
for each region's data endpoint. The first two are the usual suspects; the third is the one
that fails only in the geo-replicated case.

**The modules disagree on defaults.** Retention of untagged manifests (Terraform 7 days, Bicep
15), the trusted-service bypass (Terraform `None`, Bicep `AzureServices`) and the export policy
(Terraform on, Bicep off) differ; both leave public access unset or on. Every decision is
written on the call.

**Retention deletes only untagged manifests.** A tagged image is never touched by it. A tag
that is moved leaves the old image untagged and subject to the policy.

**Content trust is not offered.** The Docker content trust feature this tier once had is being
retired; image signing is a supply-chain decision with its own set.

**Admin user is off, and `docker login` with it.** A person or a script that used the admin
user now signs in with `az acr login` and a role.

**Log category names are the platform's.** Checked against `az monitor diagnostic-settings
categories list --resource <registry id>` before a render.

## Not covered here, and why

ACR tasks and build agents, webhooks, scope maps and tokens, cache rules (pull-through),
connected registries, image signing, vulnerability scanning (Defender), and attribute-based
repository permissions each carry decisions of their own and have no question set; a request
for one is said out loud, not improvised.

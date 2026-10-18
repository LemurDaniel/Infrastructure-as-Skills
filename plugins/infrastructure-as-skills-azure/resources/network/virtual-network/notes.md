# Virtual network — what the question set cannot express

## Fixed at creation

- **The address space.** Editable on paper, not in practice: a range can only shrink into
  space no subnet occupies, so changing it means emptying every subnet in it first.
- **A subnet delegation.** Removable only once the delegated service has nothing left in
  the subnet, and the service's own resources are not always visible as subnet members.
- **The region.** A vnet is regional; another region means another network and a peering.

## Ordering

1. Resource group
2. Virtual network
3. Subnets
4. NSGs and route tables, then their associations
5. Private endpoints — last, because they take an address from the subnet

Deletion runs the other way and the middle steps are where it fails: a subnet holding a
private endpoint, a container instance or a delegated service refuses to go, and the error
names the child rather than the dependency chain. `terraform destroy` on a network with
endpoints from another configuration in it is the common version of this.

## Pitfalls

**Five addresses per subnet are reserved** — the first four and the last. A `/29` has
three usable addresses, not eight, and a `/31` and `/32` are not valid subnets at all.

**Inline subnets versus separate subnet resources.** Azure's API lets a vnet carry its
subnets, and also lets subnets be managed on their own. Terraform exposes both, and using
both in one configuration makes each apply revert the other's changes — a plan that is
never empty. This family renders subnets as separate resources; a repository already using
inline ones keeps them.

**Custom DNS servers break private endpoint resolution** unless the privatelink zones are
forwarded to Azure DNS (168.63.129.16). The symptom is the worst kind: the name resolves,
to the resource's *public* address, so connectivity works and the traffic silently leaves
the private path.

**`private_endpoint_network_policies` defaulted to disabled for years.** Templates copied
from that era carry a subnet whose NSG rules do not apply to endpoint traffic while
appearing to. Enabled is the right default now.

**A subnet cannot be shrunk while in use** and cannot overlap another in the same vnet.
Growing it requires free adjacent space, which is the argument for leaving gaps in the
plan rather than allocating contiguously from the start.

**Peering is not transitive.** Spoke A peered to a hub does not reach spoke B through it
without a gateway, route table or firewall in the hub doing the forwarding.

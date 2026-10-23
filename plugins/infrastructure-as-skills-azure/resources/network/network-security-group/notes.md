# Network Security Group - what the question set cannot express

## Fixed at creation

- **The region.** An NSG is associated only with subnets of its own region.
- **A rule's name.** It must be unique in the group, and changing it forces the rule to be
  recreated.
- **Nothing else** - rules and priorities are edited in place, which is exactly why they are
  reviewed as code.

## Ordering

The NSG before the subnet that is associated with it: the subnet takes the NSG's resource id,
so the association is made in the virtual-network set, in the same deployment or after. An
NSG created after its subnet filters nothing until someone associates it. The workspace before
the diagnostic setting.

## Baseline by subnet purpose

`subnet_purpose` selects the rules that are written before the customer's `rules`. They are the
starting point, not a substitute for the service's documentation, and each is confirmed against
the platform's current requirements before a render (service tags and ports move).

| Purpose | Inbound | Outbound |
|---|---|---|
| `private_endpoints` | Allow `VirtualNetwork` to the endpoints on 443 (and the ports of the service behind it); deny the rest | Deny `Internet` (nothing goes out of this subnet) |
| `app_integration` | Nothing inbound is needed for outbound integration; deny the rest | Allow to the dependencies the app calls; the platform's own needs per its documentation |
| `container_apps` | The platform's required inbound for the environment type | The platform's required outbound (registry, monitoring); read from the service documentation |
| `workload` | What the workload listens on, from the sources that call it | What the workload calls |

For `private_endpoints` the NSG only takes effect when the subnet's `privateEndpointNetworkPolicies`
is enabled; without it the endpoint ignores the NSG. That is a property of the subnet, in the
virtual-network set.

## Pitfalls

**An NSG with no custom rules is open to the whole network.** The built-in inbound rules allow
every address in the virtual network and the load balancer. `default_inbound: deny_all` writes
the deny explicitly at the bottom of the custom range, so it is in the plan.

**Priorities collide and lower wins.** A priority is unique in the group, 100 to 4096 for
custom rules, and the first match ends evaluation. An allow at 200 and a deny at 300 for the
same flow allows it.

**`*` is not harmless.** A source of `*` or `Internet` on an inbound allow is the finding;
the guardrails reject it. Service tags (`Storage`, `AzureMonitor`) are narrower than any range
and follow the service's addresses, which ranges do not.

**Outbound denial moves the failure.** Denying `Internet` outbound breaks anything that calls
a control plane or a registry directly until the traffic has an allowed or routed path. It is
raised once the egress path exists, and is the reason for the default.

**Rule changes re-evaluate new flows only.** Existing connections continue until they end
unless flow re-evaluation is on (`flushConnection` in Bicep; it has its own prerequisites).
A rule that closes a hole does not cut a connection already open through it.

**The log is not traffic.** The diagnostic categories record events and rule counters; seeing
what was allowed and denied needs flow logs on Network Watcher, which this set does not create.

**Log category names are the platform's.** Checked against `az monitor diagnostic-settings
categories list --resource <nsg id>` before a render.

## Not covered here, and why

Flow logs and traffic analytics, application security groups, service-specific rule sets,
route tables, Azure Firewall and an NSG per network interface each carry decisions of their own
and have no question set; a request for one is said out loud, not improvised.

# Design decisions

One short record per decision: the context, the decision, the alternatives considered and the consequences. Names are shown with the default prefix `contoso`.

**Decisions:** [1 Hub-and-spoke](#1-hub-and-spoke-topology) · [2 Firewall Basic](#2-azure-firewall-basic) · [3 Egress through the firewall](#3-private-subnets-egress-through-the-firewall) · [4 NSGs and ASGs](#4-an-nsg-per-tier-with-application-security-groups) · [5 Bastion](#5-bastion-instead-of-public-ips) · [6 Private endpoint](#6-private-endpoint-instead-of-a-service-endpoint) · [7 GatewaySubnet](#7-gatewaysubnet-reserved-for-the-hybrid-connection) · [8 Terraform layout](#8-terraform-layout)

## 1. Hub-and-spoke topology

**Context.** Several workloads need the same shared services: a firewall, admin access and, later, a VPN to on-premises. Today there is a three-tier application; an AKS cluster comes later. Traffic must be inspected in one place.

**Decision.** One hub VNet (10.0.0.0/16) holds the shared services. Each workload gets its own spoke VNet: `vnet-contoso-app` (10.1.0.0/16) and `vnet-contoso-aks` (10.2.0.0/16). Each spoke peers with the hub, one link per direction, and with nothing else.

**Alternatives.**

- One large VNet with many subnets: simpler, but every workload shares one network and one blast radius.
- A full mesh of peerings: no central inspection point, and the number of peerings grows quickly with each new VNet.
- Azure Virtual WAN: Microsoft-managed hubs; worth it with many branches or regions.
- Azure Virtual Network Manager: builds and manages hub-and-spoke or mesh topologies at scale; not needed for three VNets.

**Consequences.**

- Peering isn't transitive. Traffic between spokes has to go through the hub firewall, which needs route tables (decision 3).
- A new workload means one new spoke VNet, two peerings (one of them is created on the hub VNet) and its range added to the firewall rules (`local.spoke_ranges`). The hub's address plan and services stay as they are.
- Every spoke depends on the hub's services.

## 2. Azure Firewall Basic

**Context.** Outbound traffic must be filtered by destination name, one web application must be published to the internet, and blocked traffic must show up in logs. The lab runs on a small budget.

**Decision.** Azure Firewall Basic in `AzureFirewallSubnet` (10.0.0.0/26), managed by a Basic firewall policy. One rule collection group holds three collections, processed in this order:

| Priority | Collection | Type | Rule |
|---|---|---|---|
| 100 | `dnat-web` | DNAT | TCP 443 on the firewall's public IP to 10.1.1.4:443, only from `web_allowed_source` |
| 200 | `net-platform` | Network | Both spokes to the `AzureMonitor` service tag on TCP 443 |
| 300 | `app-egress` | Application | Both spokes to `*.ubuntu.com` over HTTP and HTTPS |

Basic always has a management IP configuration, so the hub also has `AzureFirewallManagementSubnet` (10.0.0.64/26) and a second public IP.

**Alternatives.**

- Firewall Standard: DNS proxy, domain names in network rules, threat intelligence that can deny, web categories, up to 30 Gbps.
- Firewall Premium: Standard plus IDPS, TLS inspection and URL filtering.
- A third-party network virtual appliance: possible, but I would have to run its high availability, scaling and patching myself.
- NSGs plus a NAT gateway: no filtering by domain name, and flow logs show only IP addresses and ports, not the domain names that were allowed or blocked.

**Consequences.**

- Throughput is limited to 250 Mbps.
- Threat intelligence can only alert; it can't deny.
- Basic has no DNS proxy, so domain names work only in application rules (HTTP, HTTPS and MSSQL).
- One more /26 subnet and one more public IP, for management traffic.
- The firewall is billed by the hour while it exists, which is why the sandbox scripts stop short of creating it.

## 3. Private subnets, egress through the firewall

**Context.** Azure has long given VMs implicit internet access, called default outbound access, through a Microsoft-owned IP that can change without notice. With API versions released after 31 March 2026, subnets in new VNets are private by default, and the Azure portal already makes them private. The azurerm 4.x provider still defaults to `default_outbound_access_enabled = true`.

**Decision.**

- Every subnet except the four special ones sets `default_outbound_access_enabled = false`. `AzureFirewallSubnet`, `AzureFirewallManagementSubnet`, `AzureBastionSubnet` and `GatewaySubnet` keep it `true`, the azurerm 4.x default: they host Azure-managed services that handle their own outbound access.
- Each spoke has a route table that sends 0.0.0.0/0 to the firewall's private IP (next hop type: virtual appliance). The app spoke's table is attached to `snet-web`, `snet-app` and `snet-data`; the AKS spoke's table to `snet-aks-nodes`.
- Gateway route propagation is off on these route tables.
- The firewall denies by default and allows only Azure Monitor and Ubuntu updates (decision 2), apart from Azure's built-in infrastructure rule collection for a few platform FQDNs.

**Alternatives.**

- A NAT gateway on each subnet: a stable outbound IP and plenty of SNAT ports, but no filtering.
- Public IPs on the VMs: every VM exposed.
- Keep default outbound access: implicit, unfiltered, and being phased out (the portal and API versions released after 31 March 2026 make new subnets private).

**Consequences.**

- Every new outbound dependency needs a firewall rule. Until it exists, the traffic is denied, and the firewall logs show what was blocked.
- The default route also catches Azure's public endpoints, so Azure services need rules too (here, the `AzureMonitor` service tag).
- Traffic to the hub's own range stays direct: the peering route (10.0.0.0/16) is more specific than 0.0.0.0/0.
- Traffic between the spokes goes through the firewall and is denied until a rule allows it.
- Routes learned by a future VPN gateway don't reach the spokes, so traffic to on-premises will also go through the firewall.
- Terraform reads the next hop from the firewall resource instead of hard-coding it. The firewall's private IP can change if the firewall is stopped and started; the next `terraform apply` then writes the new address into the routes.

## 4. An NSG per tier, with application security groups

**Context.** The application has three tiers. Each tier may be reached only by the tier before it, on one port. VMs will come and go, so rules based on IP addresses would drift.

**Decision.** Each tier gets one subnet, one NSG (network security group: a stateful list of allow and deny rules) and one ASG (application security group: a label you attach to VM network interfaces, which NSG rules can name). Every NSG has the same shape:

| Priority | Purpose | Source | Destination | Port |
|---|---|---|---|---|
| 100 | The previous tier | web: AzureFirewallSubnet; app: `asg-contoso-web`; data: `asg-contoso-app` | The tier's ASG | web 443, app 8080, data 5432 |
| 110 | Admin access | AzureBastionSubnet | Any | 22, 3389 |
| 3900 | Load balancer health probes | `AzureLoadBalancer` service tag | Any | Any |
| 4000 | Deny the rest | `VirtualNetwork` service tag | Any | Any |

Azure's default rules (priority 65000 and up) stay underneath.

**Alternatives.**

- One NSG shared by all subnets: fewer resources, but every change touches every tier.
- Rules with IP addresses: they break when VMs change.
- NSGs on network interfaces: harder to audit than one NSG per subnet.
- Filtering between tiers on the firewall: needs extra routes inside the VNet and adds cost and latency. NSGs are the usual tool for segmentation inside a VNet.

**Consequences.**

- The `VirtualNetwork` tag covers the VNet's own range, peered VNets, connected on-premises ranges, Azure's host IP (168.63.129.16) and the prefixes of user-defined routes. The three tier subnets have a 0.0.0.0/0 route, so the tag matches every source and rule 4000 acts as a deny-all. It blocks VMs of the same tier from reaching each other, and traffic from the other spoke or from on-premises, even when the firewall allows it. Every new flow needs its own allow rule with a priority number lower than 4000 (lower numbers are processed first).
- Rule 3900 keeps load balancer health probes working despite the deny rule.
- The web rule allows the firewall's subnet, not the internet: Azure Firewall also source-NATs the traffic it publishes with DNAT. As a result, the web VMs don't see client IP addresses.
- All network interfaces in an ASG must be in the same VNet, which fits one spoke per application.
- No NSG on `AzureFirewallSubnet` or `GatewaySubnet`: Azure doesn't support NSGs there. `AzureBastionSubnet` could take one, but only with the rules Bastion requires; it has none here.

## 5. Bastion instead of public IPs

**Context.** Admins need SSH and RDP to VMs in the spokes. No VM may have a public IP, and no management port may face the internet.

**Decision.** Azure Bastion Basic in the hub's `AzureBastionSubnet` (10.0.1.0/26), with a static Standard public IP. Admins connect from the Azure portal over HTTPS. Bastion reaches VMs in the peered spokes on their private IPs. Rule 110 on each tier's NSG allows ports 22 and 3389 only from the Bastion subnet.

**Alternatives.**

- A public IP per VM with an NSG rule for the admin's IP: exposes every VM, and the rule needs updating whenever the admin's IP changes.
- Just-in-time VM access (a Microsoft Defender for Servers Plan 2 feature): keeps the management ports closed and opens them only on request, for a limited time. It controls when a port is open, not how admins reach the VM, so it would complement Bastion rather than replace it.
- Point-to-site VPN: full network access for admins, and more to run.
- Bastion Developer: free, but no support for peered VNets, and one VM at a time.
- Bastion Standard or Premium: native client support, file transfer and scaling; Premium adds session recording and a deployment without a public IP.

**Consequences.**

- One Bastion in the hub serves every peered spoke.
- Basic means browser sessions only: no native client and no file transfer.
- Basic has a fixed capacity of two instances.
- Bastion is billed by the hour while it exists. Moving up a tier is an in-place upgrade; moving down means deleting it and creating it again.

## 6. Private endpoint instead of a service endpoint

**Context.** The application's storage account must not be reachable from the internet. The app spoke needs it now; on-premises may need it once the VPN exists.

**Decision.**

- The storage account has public network access disabled, TLS 1.2 as the minimum and anonymous blob access off.
- A private endpoint for the blob service sits in `snet-pe` (10.1.4.0/24). It gives the account a private IP in the app VNet.
- The `privatelink.blob.core.windows.net` zone is linked to all three VNets. The endpoint's DNS zone group writes the A record, so the account's usual name, `<account>.blob.core.windows.net`, resolves to the private IP inside the VNets.

**Alternatives.**

- A service endpoint: free and simple, but the account keeps its public endpoint. It works only from the chosen subnets, not from on-premises, and the subnet's path to Storage is open to every storage account, not just this one, unless a service endpoint policy narrows it.
- The public endpoint with storage firewall rules: still reachable from the internet.

**Consequences.**

- DNS becomes part of the design. Every VNet that uses the account needs a link to the privatelink zone, or a central DNS service that forwards to Azure DNS.
- On-premises clients will need DNS forwarding (for example, Azure DNS Private Resolver) as well as the VPN.
- A private endpoint has an hourly charge plus a charge for the data it processes.
- Each storage service needs its own endpoint: blob now; file, queue or table later.
- Traffic from the app tiers to the endpoint stays inside the VNet and doesn't cross the firewall.
- When Terraform runs outside the VNet, its calls to the account's data plane get HTTP 403 (public access is off). So `providers.tf` turns off the provider's storage data-plane checks (`data_plane_available = false`).

## 7. GatewaySubnet reserved for the hybrid connection

**Context.** A later step connects an on-premises network (192.168.0.0/16) through a site-to-site VPN. A VPN gateway needs a subnet named exactly `GatewaySubnet`, and the address plan is the hardest thing to change once resources use it.

**Decision.** `GatewaySubnet` (10.0.2.0/27) exists in the hub now, empty. The peerings don't use a gateway yet: `allow_gateway_transit` (hub side) and `use_remote_gateways` (spoke side) stay false until a gateway exists.

**Alternatives.**

- Create the VPN gateway now: it is billed by the hour and slow to deploy, and there is nothing to connect yet.
- Reserve nothing: later, the hub might have no free range of the right size.
- A /26 or larger: needed for some configurations, such as an ExpressRoute gateway connected to 16 circuits; every VPN gateway SKU except Basic needs at least a /27.

**Consequences.**

- No NSG and no 0.0.0.0/0 route on `GatewaySubnet`: Azure doesn't support them there.
- When the gateway arrives, turn on gateway transit on the hub's peerings and "use remote gateways" on the spokes' peerings.
- The spoke route tables already ignore gateway routes, so traffic from the spokes to on-premises will go through the firewall.
- The return path needs a route table on `GatewaySubnet` that sends each spoke's exact range (10.1.0.0/16 and 10.2.0.0/16) to the firewall, with gateway route propagation left on there, because the gateway needs it.
- The on-premises range doesn't overlap any Azure range (all three VNets sit inside 10.0.0.0/14), so the VPN can route between them without NAT.

## 8. Terraform layout

One address-plan map, `for_each` for every repeated resource, no modules.

**Context.** One environment, three VNets, ten subnets, and three tiers with nearly identical rules. The code must be easy to read and review, and adding a subnet or a spoke shouldn't mean copying blocks.

**Decision.**

- `locals.tf` holds the address plan as one map, `local.vnets`: each VNet with its subnets, their prefixes and whether they are private. A `for` expression flattens it into `local.subnets`, keyed like `app/snet-web`.
- Every repeated resource uses `for_each` over these maps or sets: VNets, subnets, peerings, ASGs, NSGs, DNS links, route tables and associations.
- `local.tier_ingress` holds the one NSG rule that differs per tier; the other rules are written once.
- One file per area (network, peering, security, DNS, firewall, routing, Bastion, storage, monitoring), and no modules.
- The resource group is read with a `data` source, because the sandbox provides it.
- Provider versions are constrained with `~>` (azurerm 4.x, random 3.6 or later in 3.x) and pinned to exact builds by the committed lock file.

**Alternatives.**

- Modules, my own or Azure Verified Modules: useful with many environments or teams, but extra layers for one small configuration.
- `count`: removing an item from the middle of a list shifts the indexes, so Terraform destroys and recreates the wrong resources.
- One resource block per subnet or rule: longer, and the copies drift apart.
- Bicep: a good fit for Azure-only work too; this lab set out to practise Terraform.

**Consequences.**

- Keys are stable names, so removing one subnet doesn't touch the others.
- The Azure names are built from the keys, so renaming a key also renames the Azure resource. Azure can't rename these resources, so Terraform destroys and recreates it. A `moved` block avoids that only when the key changes and the name stays the same.
- Adding a spoke means a new entry in `local.vnets`, plus its name in `local.spokes`, its range in `local.spoke_ranges` and its workload subnets in `local.routed_subnets`. The DNS links pick up new VNets on their own.
- For several environments, I would move to modules or one root folder per environment, with remote state.

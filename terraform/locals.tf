locals {
  tags = {
    project     = "network-foundation"
    environment = "lab"
    owner       = "platform-team"
  }

  # The address plan: hub 10.0.0.0/16 and one /16 per spoke.
  # On-premises (Project 2) will be 192.168.0.0/16, so nothing overlaps.
  vnets = {
    hub = {
      address_space = ["10.0.0.0/16"]
      subnets = {
        AzureFirewallSubnet           = { prefix = "10.0.0.0/26", private = false }
        AzureFirewallManagementSubnet = { prefix = "10.0.0.64/26", private = false }
        AzureBastionSubnet            = { prefix = "10.0.1.0/26", private = false }
        GatewaySubnet                 = { prefix = "10.0.2.0/27", private = false }
        snet-shared                   = { prefix = "10.0.3.0/24", private = true }
      }
    }
    app = {
      address_space = ["10.1.0.0/16"]
      subnets = {
        snet-web  = { prefix = "10.1.1.0/24", private = true }
        snet-app  = { prefix = "10.1.2.0/24", private = true }
        snet-data = { prefix = "10.1.3.0/24", private = true }
        snet-pe   = { prefix = "10.1.4.0/24", private = true }
      }
    }
    aks = {
      address_space = ["10.2.0.0/16"]
      subnets = {
        snet-aks-nodes = { prefix = "10.2.0.0/22", private = true }
      }
    }
  }

  # Flatten "vnet -> subnets" into one map, so one resource block creates every subnet.
  # Keys look like "app/snet-web".
  subnets = merge([
    for vnet_key, vnet in local.vnets : {
      for subnet_name, subnet in vnet.subnets :
      "${vnet_key}/${subnet_name}" => {
        vnet_key = vnet_key
        name     = subnet_name
        prefix   = subnet.prefix
        private  = subnet.private
      }
    }
  ]...)

  spokes       = toset(["app", "aks"])
  spoke_ranges = concat(local.vnets.app.address_space, local.vnets.aks.address_space)

  # Workload subnets whose internet-bound traffic must go through the firewall
  routed_subnets = toset([
    "app/snet-web",
    "app/snet-app",
    "app/snet-data",
    "aks/snet-aks-nodes",
  ])

  firewall_subnet_prefix = local.vnets.hub.subnets.AzureFirewallSubnet.prefix
  bastion_subnet_prefix  = local.vnets.hub.subnets.AzureBastionSubnet.prefix

  # First usable address of snet-web (.0 to .3 are reserved by Azure): the web VM behind DNAT
  web_vm_ip = cidrhost(local.vnets.app.subnets["snet-web"].prefix, 4)

  # The one inbound rule that differs per tier: who may reach it, on which port
  tier_ingress = {
    web  = { source_prefix = local.firewall_subnet_prefix, source_asg = null, port = "443" }
    app  = { source_prefix = null, source_asg = "web", port = "8080" }
    data = { source_prefix = null, source_asg = "app", port = "5432" }
  }
}

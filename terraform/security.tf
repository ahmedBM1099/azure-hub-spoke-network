resource "azurerm_application_security_group" "tier" {
  for_each = local.tier_ingress

  name                = "asg-${var.prefix}-${each.key}"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.rg.name
  tags                = local.tags
}

locals {
  asg_ids = { for tier, asg in azurerm_application_security_group.tier : tier => asg.id }
}

resource "azurerm_network_security_group" "tier" {
  for_each = local.tier_ingress

  name                = "nsg-${var.prefix}-${each.key}"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.rg.name
  tags                = local.tags

  # Only the previous tier may come in (for web: the firewall, which SNATs DNAT traffic)
  security_rule {
    name                   = "allow-${each.value.port}-from-previous-tier"
    priority               = 100
    direction              = "Inbound"
    access                 = "Allow"
    protocol               = "Tcp"
    source_port_range      = "*"
    destination_port_range = each.value.port
    source_address_prefix  = each.value.source_prefix
    source_application_security_group_ids = (
      each.value.source_asg == null ? null : [local.asg_ids[each.value.source_asg]]
    )
    destination_application_security_group_ids = [local.asg_ids[each.key]]
  }

  security_rule {
    name                       = "allow-admin-from-bastion"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["22", "3389"]
    source_address_prefix      = local.bastion_subnet_prefix
    destination_address_prefix = "*"
  }

  # Keep health probes working above the broad deny below
  security_rule {
    name                       = "allow-azure-load-balancer"
    priority                   = 3900
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  # Beats the default AllowVnetInBound (65000): peered VNets and other subnets stay out
  security_rule {
    name                       = "deny-other-vnet-inbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "tier" {
  for_each = local.tier_ingress

  subnet_id                 = azurerm_subnet.this["app/snet-${each.key}"].id
  network_security_group_id = azurerm_network_security_group.tier[each.key].id
}

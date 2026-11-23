resource "azurerm_public_ip" "firewall" {
  name                = "pip-${var.prefix}-fw"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

# Firewall Basic always needs a second, management IP configuration
resource "azurerm_public_ip" "firewall_mgmt" {
  name                = "pip-${var.prefix}-fw-mgmt"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_firewall_policy" "hub" {
  name                = "afwp-${var.prefix}-hub"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.rg.name
  sku                 = "Basic"
  tags                = local.tags
}

resource "azurerm_firewall" "hub" {
  name                = "afw-${var.prefix}-hub"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.rg.name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Basic"
  firewall_policy_id  = azurerm_firewall_policy.hub.id
  tags                = local.tags

  ip_configuration {
    name                 = "ipconfig"
    subnet_id            = azurerm_subnet.this["hub/AzureFirewallSubnet"].id
    public_ip_address_id = azurerm_public_ip.firewall.id
  }

  management_ip_configuration {
    name                 = "mgmt-ipconfig"
    subnet_id            = azurerm_subnet.this["hub/AzureFirewallManagementSubnet"].id
    public_ip_address_id = azurerm_public_ip.firewall_mgmt.id
  }
}

# Processing order inside the firewall: DNAT, then network, then application rules
resource "azurerm_firewall_policy_rule_collection_group" "hub" {
  name               = "rcg-${var.prefix}-hub"
  firewall_policy_id = azurerm_firewall_policy.hub.id
  priority           = 100

  nat_rule_collection {
    name     = "dnat-web"
    priority = 100
    action   = "Dnat"

    rule {
      name                = "https-to-web"
      protocols           = ["TCP"]
      source_addresses    = [var.web_allowed_source]
      destination_address = azurerm_public_ip.firewall.ip_address
      destination_ports   = ["443"]
      translated_address  = local.web_vm_ip
      translated_port     = 443
    }
  }

  # Spoke-to-spoke stays closed: nothing here allows app <-> aks yet
  network_rule_collection {
    name     = "net-platform"
    priority = 200
    action   = "Allow"

    rule {
      name                  = "spokes-to-azure-monitor"
      protocols             = ["TCP"]
      source_addresses      = local.spoke_ranges
      destination_addresses = ["AzureMonitor"] # service tag, kept current by Microsoft
      destination_ports     = ["443"]
    }
  }

  application_rule_collection {
    name     = "app-egress"
    priority = 300
    action   = "Allow"

    rule {
      name              = "os-updates"
      source_addresses  = local.spoke_ranges
      destination_fqdns = ["*.ubuntu.com"]

      protocols {
        type = "Http"
        port = 80
      }
      protocols {
        type = "Https"
        port = 443
      }
    }
  }
}

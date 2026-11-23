resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  for_each = local.spokes

  name                      = "peer-hub-to-${each.key}"
  resource_group_name       = data.azurerm_resource_group.rg.name
  virtual_network_name      = azurerm_virtual_network.this["hub"].name
  remote_virtual_network_id = azurerm_virtual_network.this[each.key].id
  allow_forwarded_traffic   = true
  allow_gateway_transit     = false # true in Project 2, once the hub has a VPN gateway
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  for_each = local.spokes

  name                      = "peer-${each.key}-to-hub"
  resource_group_name       = data.azurerm_resource_group.rg.name
  virtual_network_name      = azurerm_virtual_network.this[each.key].name
  remote_virtual_network_id = azurerm_virtual_network.this["hub"].id
  allow_forwarded_traffic   = true  # accept packets the hub firewall forwards from the other spoke
  use_remote_gateways       = false # true in Project 2, after the hub gateway exists
}

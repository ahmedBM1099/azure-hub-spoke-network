resource "azurerm_route_table" "spokes" {
  for_each = local.spokes

  name                = "rt-${var.prefix}-${each.key}"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.rg.name
  tags                = local.tags

  # On-premises routes learned by the VPN gateway (Project 2) must not bypass the firewall
  bgp_route_propagation_enabled = false

  # Peered hub ranges (10.0.0.0/16) stay direct: a longer prefix beats 0.0.0.0/0
  route {
    name                   = "default-to-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.hub.ip_configuration[0].private_ip_address
  }
}

resource "azurerm_subnet_route_table_association" "this" {
  for_each = local.routed_subnets

  subnet_id      = azurerm_subnet.this[each.key].id
  route_table_id = azurerm_route_table.spokes[split("/", each.key)[0]].id
}

data "azurerm_resource_group" "rg" {
  name = var.resource_group_name
}

resource "azurerm_virtual_network" "this" {
  for_each = { for key, vnet in local.vnets : key => vnet.address_space }

  name                = "vnet-${var.prefix}-${each.key}"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.rg.name
  address_space       = each.value
  tags                = local.tags
}

resource "azurerm_subnet" "this" {
  for_each = local.subnets

  name                            = each.value.name
  resource_group_name             = data.azurerm_resource_group.rg.name
  virtual_network_name            = azurerm_virtual_network.this[each.value.vnet_key].name
  address_prefixes                = [each.value.prefix]
  default_outbound_access_enabled = !each.value.private
}

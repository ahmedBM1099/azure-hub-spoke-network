resource "azurerm_private_dns_zone" "internal" {
  name                = "${var.prefix}.internal"
  resource_group_name = data.azurerm_resource_group.rg.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "internal" {
  for_each = azurerm_virtual_network.this

  name                  = "link-${each.key}"
  resource_group_name   = data.azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.internal.name
  virtual_network_id    = each.value.id
  registration_enabled  = each.key != "aks" # hub and app VMs register; AKS doesn't need to
  tags                  = local.tags
}

# Used by the storage private endpoint (storage.tf)
resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = data.azurerm_resource_group.rg.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  for_each = azurerm_virtual_network.this

  name                  = "link-blob-${each.key}"
  resource_group_name   = data.azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = each.value.id
  registration_enabled  = false
  tags                  = local.tags
}

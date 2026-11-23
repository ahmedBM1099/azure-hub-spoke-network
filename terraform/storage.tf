resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# Storage names are global: 3-24 lowercase letters/digits, so a random suffix avoids clashes
resource "azurerm_storage_account" "data" {
  name                            = "st${var.prefix}${random_string.suffix.result}"
  resource_group_name             = data.azurerm_resource_group.rg.name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  public_network_access_enabled   = false # reachable only through the private endpoint
  allow_nested_items_to_be_public = false
  tags                            = local.tags
}

resource "azurerm_private_endpoint" "blob" {
  name                = "pe-${azurerm_storage_account.data.name}-blob"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.this["app/snet-pe"].id
  tags                = local.tags

  private_service_connection {
    name                           = "psc-blob"
    private_connection_resource_id = azurerm_storage_account.data.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  # Writes the A record (storage name -> private IP) into privatelink.blob.core.windows.net
  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }
}

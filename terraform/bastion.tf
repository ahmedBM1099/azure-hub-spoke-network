resource "azurerm_public_ip" "bastion" {
  name                = "pip-${var.prefix}-bastion"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_bastion_host" "hub" {
  name                = "bas-${var.prefix}-hub"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.rg.name
  sku                 = "Basic"
  tags                = local.tags

  ip_configuration {
    name                 = "ipconfig"
    subnet_id            = azurerm_subnet.this["hub/AzureBastionSubnet"].id
    public_ip_address_id = azurerm_public_ip.bastion.id
  }
}

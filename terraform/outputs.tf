output "firewall_private_ip" {
  description = "Next hop for every spoke's default route"
  value       = azurerm_firewall.hub.ip_configuration[0].private_ip_address
}

output "firewall_public_ip" {
  description = "Public entry point (DNAT to the web VM)"
  value       = azurerm_public_ip.firewall.ip_address
}

output "web_vm_ip" {
  description = "Private IP the DNAT rule translates to"
  value       = local.web_vm_ip
}

output "vnet_ids" {
  value = { for key, vnet in azurerm_virtual_network.this : key => vnet.id }
}

output "storage_account_name" {
  value = azurerm_storage_account.data.name
}

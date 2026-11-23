# Project 1 - step 2 fast path: the three VNets and all their subnets.
# Paste ALL of this into the playground's Cloud Shell (PowerShell): it runs as one block.
& {
$rg = az group list --query "[0].name" -o tsv
$loc = az group list --query "[0].location" -o tsv
$ErrorActionPreference = "Stop"; $PSNativeCommandUseErrorActionPreference = $true
Write-Host "Resource group: $rg ($loc)"
# Hub: the special subnets keep the default outbound setting; snet-shared is private
az network vnet create -g $rg -n vnet-contoso-hub -l $loc --address-prefixes 10.0.0.0/16 -o none
$hub = [ordered]@{
    AzureFirewallSubnet           = "10.0.0.0/26"
    AzureFirewallManagementSubnet = "10.0.0.64/26"
    AzureBastionSubnet            = "10.0.1.0/26"
    GatewaySubnet                 = "10.0.2.0/27"
}
foreach ($s in $hub.GetEnumerator()) {
    az network vnet subnet create -g $rg --vnet-name vnet-contoso-hub -n $s.Key `
        --address-prefixes $s.Value -o none
}
az network vnet subnet create -g $rg --vnet-name vnet-contoso-hub -n snet-shared `
    --address-prefixes 10.0.3.0/24 --default-outbound false -o none
# App spoke: four private subnets
az network vnet create -g $rg -n vnet-contoso-app -l $loc --address-prefixes 10.1.0.0/16 -o none
$app = [ordered]@{
    "snet-web"  = "10.1.1.0/24"
    "snet-app"  = "10.1.2.0/24"
    "snet-data" = "10.1.3.0/24"
    "snet-pe"   = "10.1.4.0/24"
}
foreach ($s in $app.GetEnumerator()) {
    az network vnet subnet create -g $rg --vnet-name vnet-contoso-app -n $s.Key `
        --address-prefixes $s.Value --default-outbound false -o none
}
# AKS spoke
az network vnet create -g $rg -n vnet-contoso-aks -l $loc --address-prefixes 10.2.0.0/16 -o none
az network vnet subnet create -g $rg --vnet-name vnet-contoso-aks -n snet-aks-nodes `
    --address-prefixes 10.2.0.0/22 --default-outbound false -o none
az network vnet list -g $rg `
    --query "[].{name:name, range:addressSpace.addressPrefixes[0], subnets:length(subnets)}" -o table
Write-Host "Step 2 done" -ForegroundColor Green
}

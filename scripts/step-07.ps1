# Project 1 - step 7 fast path: route tables that send each spoke's 0.0.0.0/0 to the firewall.
# Needs step 2. Paste ALL of this into the playground's Cloud Shell (PowerShell).
& {
$rg = az group list --query "[0].name" -o tsv
$loc = az group list --query "[0].location" -o tsv
az network vnet show -g $rg -n vnet-contoso-app -o none 2>$null
if ($LASTEXITCODE) { throw "vnet-contoso-app is missing: run step-02.ps1 first" }
$aks = az network vnet list -g $rg --query "[?name=='vnet-contoso-aks'].name" -o tsv
$ErrorActionPreference = "Stop"; $PSNativeCommandUseErrorActionPreference = $true
# 10.0.0.4 is the firewall's private IP: the first usable address of AzureFirewallSubnet
$spokes = if ($aks) { "app", "aks" } else { "app" }
foreach ($spoke in $spokes) {
    az network route-table create -g $rg -n "rt-contoso-$spoke" -l $loc `
        --disable-bgp-route-propagation true -o none
    az network route-table route create -g $rg --route-table-name "rt-contoso-$spoke" `
        -n default-to-firewall --address-prefix 0.0.0.0/0 `
        --next-hop-type VirtualAppliance --next-hop-ip-address 10.0.0.4 -o none
}
foreach ($s in "snet-web", "snet-app", "snet-data") {
    az network vnet subnet update -g $rg --vnet-name vnet-contoso-app -n $s `
        --route-table rt-contoso-app -o none
}
if ($aks) {
    az network vnet subnet update -g $rg --vnet-name vnet-contoso-aks -n snet-aks-nodes `
        --route-table rt-contoso-aks -o none
}
az network route-table route list -g $rg --route-table-name rt-contoso-app -o table
Write-Host "Step 7 done" -ForegroundColor Green
}

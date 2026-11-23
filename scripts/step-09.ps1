# Project 1 - step 9 fast path: a storage account with public access off, reached through a
# private endpoint in snet-pe, and the privatelink zone that resolves it.
# Needs step 2. Paste ALL of this into the playground's Cloud Shell (PowerShell).
& {
$rg = az group list --query "[0].name" -o tsv
$loc = az group list --query "[0].location" -o tsv
az network vnet show -g $rg -n vnet-contoso-app -o none 2>$null
if ($LASTEXITCODE) { throw "vnet-contoso-app is missing: run step-02.ps1 first" }
$zone = "privatelink.blob.core.windows.net"
$hasZone = az network private-dns zone list -g $rg --query "[?name=='$zone'].name" -o tsv
$ErrorActionPreference = "Stop"; $PSNativeCommandUseErrorActionPreference = $true
# Storage names are global: reuse this session's account, or make one with a random suffix
$st = az storage account list -g $rg --query "[?starts_with(name, 'stcontoso')].name | [0]" -o tsv
if (-not $st) { $st = "stcontoso$(Get-Random -Minimum 100000 -Maximum 999999)" }
az storage account create -g $rg -n $st -l $loc --sku Standard_LRS --kind StorageV2 `
    --min-tls-version TLS1_2 --public-network-access Disabled `
    --allow-blob-public-access false -o none
$stId = az storage account show -g $rg -n $st --query id -o tsv
# The privatelink zone, linked to the app VNet (the portal wizard does the same)
if (-not $hasZone) {
    az network private-dns zone create -g $rg -n $zone -o none
    az network private-dns link vnet create -g $rg -z $zone -n link-blob-app `
        -v vnet-contoso-app -e false -o none
}
az network private-endpoint create -g $rg -n "pe-$st-blob" -l $loc `
    --vnet-name vnet-contoso-app --subnet snet-pe `
    --private-connection-resource-id $stId --group-id blob --connection-name psc-blob -o none
az network private-endpoint dns-zone-group create -g $rg --endpoint-name "pe-$st-blob" `
    -n default --private-dns-zone $zone --zone-name blob -o none
Write-Host "Storage account: $st"
az network private-dns record-set a list -g $rg -z $zone `
    --query "[].{name:name, ip:aRecords[0].ipv4Address}" -o table
Write-Host "Step 9 done" -ForegroundColor Green
}

# Project 1 - step 3 fast path: peer both spokes with the hub, one link per direction.
# Needs step 2. Paste ALL of this into the playground's Cloud Shell (PowerShell).
& {
$rg = az group list --query "[0].name" -o tsv
foreach ($v in "hub", "app", "aks") {
    az network vnet show -g $rg -n "vnet-contoso-$v" -o none 2>$null
    if ($LASTEXITCODE) { throw "vnet-contoso-$v is missing: run step-02.ps1 first" }
}
$ErrorActionPreference = "Stop"; $PSNativeCommandUseErrorActionPreference = $true
foreach ($spoke in "app", "aks") {
    az network vnet peering create -g $rg -n "peer-hub-to-$spoke" --vnet-name vnet-contoso-hub `
        --remote-vnet "vnet-contoso-$spoke" --allow-vnet-access true `
        --allow-forwarded-traffic true -o none
    az network vnet peering create -g $rg -n "peer-$spoke-to-hub" --vnet-name "vnet-contoso-$spoke" `
        --remote-vnet vnet-contoso-hub --allow-vnet-access true `
        --allow-forwarded-traffic true -o none
}
az network vnet peering list -g $rg --vnet-name vnet-contoso-hub `
    --query "[].{name:name, state:peeringState}" -o table
Write-Host "Step 3 done" -ForegroundColor Green
}

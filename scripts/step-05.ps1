# Project 1 - step 5 fast path: the contoso.internal zone and its three VNet links.
# Needs step 2. Paste ALL of this into the playground's Cloud Shell (PowerShell).
& {
$rg = az group list --query "[0].name" -o tsv
foreach ($v in "hub", "app", "aks") {
    az network vnet show -g $rg -n "vnet-contoso-$v" -o none 2>$null
    if ($LASTEXITCODE) { throw "vnet-contoso-$v is missing: run step-02.ps1 first" }
}
$ErrorActionPreference = "Stop"; $PSNativeCommandUseErrorActionPreference = $true
az network private-dns zone create -g $rg -n contoso.internal -o none
# Hub and app VMs register their names; AKS only resolves
$registration = @{ hub = "true"; app = "true"; aks = "false" }
foreach ($v in "hub", "app", "aks") {
    az network private-dns link vnet create -g $rg -z contoso.internal `
        -n "link-$v" -v "vnet-contoso-$v" -e $registration[$v] -o none
}
az network private-dns link vnet list -g $rg -z contoso.internal `
    --query "[].{name:name, registration:registrationEnabled, state:virtualNetworkLinkState}" -o table
Write-Host "Step 5 done" -ForegroundColor Green
}

# Project 1 - step 4 fast path: an ASG and an NSG per tier, their rules, and the associations.
# Needs step 2. Paste ALL of this into the playground's Cloud Shell (PowerShell).
& {
$rg = az group list --query "[0].name" -o tsv
$loc = az group list --query "[0].location" -o tsv
az network vnet show -g $rg -n vnet-contoso-app -o none 2>$null
if ($LASTEXITCODE) { throw "vnet-contoso-app is missing: run step-02.ps1 first" }
$ErrorActionPreference = "Stop"; $PSNativeCommandUseErrorActionPreference = $true
foreach ($tier in "web", "app", "data") {
    az network asg create -g $rg -n "asg-contoso-$tier" -l $loc -o none
    az network nsg create -g $rg -n "nsg-contoso-$tier" -l $loc -o none
}
# Rule 100 differs per tier: who may come in, on which port
az network nsg rule create -g $rg --nsg-name nsg-contoso-web -n allow-443-from-firewall `
    --priority 100 --direction Inbound --access Allow --protocol Tcp `
    --source-address-prefixes 10.0.0.0/26 --destination-asgs asg-contoso-web `
    --destination-port-ranges 443 -o none
az network nsg rule create -g $rg --nsg-name nsg-contoso-app -n allow-8080-from-web `
    --priority 100 --direction Inbound --access Allow --protocol Tcp `
    --source-asgs asg-contoso-web --destination-asgs asg-contoso-app `
    --destination-port-ranges 8080 -o none
az network nsg rule create -g $rg --nsg-name nsg-contoso-data -n allow-5432-from-app `
    --priority 100 --direction Inbound --access Allow --protocol Tcp `
    --source-asgs asg-contoso-app --destination-asgs asg-contoso-data `
    --destination-port-ranges 5432 -o none
# Rules 110, 3900 and 4000 are the same on every tier; then attach each NSG to its subnet
foreach ($tier in "web", "app", "data") {
    $nsg = "nsg-contoso-$tier"
    az network nsg rule create -g $rg --nsg-name $nsg -n allow-admin-from-bastion --priority 110 `
        --direction Inbound --access Allow --protocol Tcp --source-address-prefixes 10.0.1.0/26 `
        --destination-address-prefixes "*" --destination-port-ranges 22 3389 -o none
    az network nsg rule create -g $rg --nsg-name $nsg -n allow-azure-load-balancer --priority 3900 `
        --direction Inbound --access Allow --protocol "*" `
        --source-address-prefixes AzureLoadBalancer `
        --destination-address-prefixes "*" --destination-port-ranges "*" -o none
    az network nsg rule create -g $rg --nsg-name $nsg -n deny-other-vnet-inbound --priority 4000 `
        --direction Inbound --access Deny --protocol "*" --source-address-prefixes VirtualNetwork `
        --destination-address-prefixes "*" --destination-port-ranges "*" -o none
    az network vnet subnet update -g $rg --vnet-name vnet-contoso-app -n "snet-$tier" `
        --network-security-group $nsg -o none
}
az network nsg rule list -g $rg --nsg-name nsg-contoso-app `
    --query "[].{name:name, priority:priority, access:access}" -o table
Write-Host "Step 4 done" -ForegroundColor Green
}

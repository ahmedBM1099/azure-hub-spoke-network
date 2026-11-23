# Project 1 - step 6 fast path: the firewall's public IP, the Basic policy and its three rule
# collections. The firewall itself stays a walk-through.
# Paste ALL of this into the playground's Cloud Shell (PowerShell).
& {
$rg = az group list --query "[0].name" -o tsv
$loc = az group list --query "[0].location" -o tsv
$ErrorActionPreference = "Stop"; $PSNativeCommandUseErrorActionPreference = $true
# The firewall commands live in an az extension: install it without asking
az config set extension.use_dynamic_install=yes_without_prompt --only-show-errors
az network public-ip create -g $rg -n pip-contoso-fw -l $loc --sku Standard `
    --allocation-method Static -o none
az network firewall policy create -g $rg -n afwp-contoso-hub -l $loc --sku Basic -o none
$fwPip = az network public-ip show -g $rg -n pip-contoso-fw --query ipAddress -o tsv
az network firewall policy rule-collection-group create -g $rg --policy-name afwp-contoso-hub `
    -n rcg-contoso-hub --priority 100 -o none
# DNAT from anywhere here; in a real setup, limit the source to known IPs
az network firewall policy rule-collection-group collection add-nat-collection -g $rg `
    --policy-name afwp-contoso-hub --rcg-name rcg-contoso-hub -n dnat-web `
    --collection-priority 100 --action DNAT --rule-name https-to-web --ip-protocols TCP `
    --source-addresses "*" --destination-addresses $fwPip --destination-ports 443 `
    --translated-address 10.1.1.4 --translated-port 443 -o none
az network firewall policy rule-collection-group collection add-filter-collection -g $rg `
    --policy-name afwp-contoso-hub --rcg-name rcg-contoso-hub -n net-platform `
    --collection-priority 200 --action Allow --rule-type NetworkRule `
    --rule-name spokes-to-azure-monitor --ip-protocols TCP `
    --source-addresses 10.1.0.0/16 10.2.0.0/16 `
    --destination-addresses AzureMonitor --destination-ports 443 -o none
az network firewall policy rule-collection-group collection add-filter-collection -g $rg `
    --policy-name afwp-contoso-hub --rcg-name rcg-contoso-hub -n app-egress `
    --collection-priority 300 --action Allow --rule-type ApplicationRule --rule-name os-updates `
    --source-addresses 10.1.0.0/16 10.2.0.0/16 --target-fqdns "*.ubuntu.com" `
    --protocols Http=80 Https=443 -o none
az network firewall policy rule-collection-group show -g $rg --policy-name afwp-contoso-hub `
    -n rcg-contoso-hub --query "ruleCollections[].{name:name, priority:priority}" -o table
Write-Host "Step 6 done: now walk through the firewall wizard (Firewalls, + Create)" -ForegroundColor Green
}

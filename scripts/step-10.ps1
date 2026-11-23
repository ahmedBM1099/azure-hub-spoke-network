# Project 1 - step 10 fast path: a Log Analytics workspace, and a diagnostic setting that sends
# the storage account's blob logs to it.
# Needs step 9. Paste ALL of this into the playground's Cloud Shell (PowerShell).
& {
$rg = az group list --query "[0].name" -o tsv
$loc = az group list --query "[0].location" -o tsv
$st = az storage account list -g $rg --query "[?starts_with(name, 'stcontoso')].name | [0]" -o tsv
if (-not $st) { throw "No stcontoso storage account: run step-09.ps1 first" }
$ErrorActionPreference = "Stop"; $PSNativeCommandUseErrorActionPreference = $true
az monitor log-analytics workspace create -g $rg --workspace-name log-contoso-hub -l $loc `
    --retention-time 30 -o none
$lawId = az monitor log-analytics workspace show -g $rg --workspace-name log-contoso-hub `
    --query id -o tsv
# Blob logs are set on the blob service, a child of the storage account
$blobId = "$(az storage account show -g $rg -n $st --query id -o tsv)/blobServices/default"
az monitor diagnostic-settings create -n diag-blob --resource $blobId --workspace $lawId `
    --logs '[{"categoryGroup":"allLogs","enabled":true}]' `
    --metrics '[{"category":"Transaction","enabled":true}]' -o none
az monitor diagnostic-settings list --resource $blobId --query "[].name" -o tsv
Write-Host "Step 10 done: in log-contoso-hub > Logs, run StorageBlobLogs | take 10" -ForegroundColor Green
}

$azpath = which az
$folder = $PSScriptRoot    

if($azpath -like "*/az*" ) {
        Write-Host "`nAzure CLI is found...`n" -ForegroundColor Green
        $status="SUCCESS"
        $comments="Azure CLI Exists."
}
else {
    Write-Host "======================================================================================="  
    Write-Host "Azure CLI not found."  -BackgroundColor Red
    Write-Host "=======================================================================================" 
            
    Write-Host "Install the Azure CLI manually.`nPlease find the link to install Azure CLi ==> 'https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-linux?pivots=apt'" -ForegroundColor Green

    if ($azpath -ne $null) {
        $status="SUCCESS"
        $comments=" Azure CLI Exists."
    }
    else {
        $status="FAILED"
        $comments="Install the Azure CLI manually.`nPlease find the link to install Azure CLi ==> 'https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-linux?pivots=apt'"
    }
}
$Output = New-Object psobject -Property @{Validation_Type="Check Azure CLI is available";Status =$status;Comments=$comments}
return $Output


    $azpath = where.exe az
    $folder = $PSScriptRoot    

    function exitCode
    {
        Write-Host "-Ending Execution"
        Stop-Transcript
        exit
    }

    function Check-Command($cmdname) {
        return [bool](Get-Command -Name $cmdname -ErrorAction SilentlyContinue)
    }
    if($azpath -ne $null) {
		Write-Host "`nAzure CLI is found...`n" -ForegroundColor Green
		$status="SUCCESS"
		$comments="Azure CLI Exists."
	}
	else {
		Write-Host "======================================================================================="  
		Write-Host "Azure CLI not found."  -BackgroundColor Red
		Write-Host "======================================================================================="
		
		$comments = "Azure CLI not found"
		Write-Host "`nAzure CLI is not found. Please install and ensure Azure CLI path is added in the environmental variables and re-execute the script again..." -ForegroundColor Red
		Write-Host "`n Download link for Azure CLI file -- 'https://aka.ms/installazurecliwindowsx64'" -ForegroundColor Magenta
		break
		}
$Output = New-Object psobject -Property @{Validation_Type="Check Azure CLI is available";Status =$status;Comments=$comments}
return $Output
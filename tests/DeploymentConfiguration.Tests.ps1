$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$deploymentScript = Join-Path $root 'infra\deploy.ps1'
$exampleParameters = Join-Path $root 'infra\main.parameters.json'
$temporaryParameters = Join-Path ([IO.Path]::GetTempPath()) "dbmigration-parameters-$([Guid]::NewGuid().ToString('N')).json"
$subscription = '00000000-0000-0000-0000-000000000000'
$tenant = '11111111-1111-1111-1111-111111111111'

function Assert-Equal {
    param($Actual, $Expected)
    if ($Actual -ne $Expected) {
        throw "Expected '$Expected', got '$Actual'."
    }
}

function Invoke-ConfigurationTest {
    param([string]$Path, [string]$ExpectedSuffix)

    & {
        $script:AzureCommands = [Collections.Generic.List[string]]::new()
        function az {
            $script:AzureCommands.Add(($args -join ' '))
            $global:LASTEXITCODE = 0
            if ($args[0] -eq 'account' -and $args[1] -eq 'show') {
                return @{ id = $subscription; tenantId = $tenant } | ConvertTo-Json
            }
            return 'mock'
        }
        function docker { $global:LASTEXITCODE = 0; return 'mock' }

        . $deploymentScript -Mode Validate -ParametersFile $Path -SubscriptionId $subscription -TenantId $tenant
        Assert-Equal $resourceGroupName "rg-$ExpectedSuffix"
        Assert-Equal $containerRegistryName "cr$($ExpectedSuffix.Replace('-', ''))"
        Assert-Equal $keyVaultName "kv-$ExpectedSuffix"
        if ($script:AzureCommands | Where-Object { $_ -match 'deployment|containerapp update|keyvault secret' }) {
            throw 'Configuration validation attempted to change Azure resources.'
        }
    }
}

try {
    Invoke-ConfigurationTest -Path $exampleParameters -ExpectedSuffix 'dbmigration-dev'

    $parameters = Get-Content -LiteralPath $exampleParameters -Raw | ConvertFrom-Json
    $parameters.parameters | Add-Member -NotePropertyName resourceNameSuffix -NotePropertyValue @{ value = 'legacy-dev' }
    $parameters | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $temporaryParameters
    Invoke-ConfigurationTest -Path $temporaryParameters -ExpectedSuffix 'legacy-dev'

    $missingContextRejected = $false
    try {
        & $deploymentScript -Mode Validate -ParametersFile $exampleParameters -SubscriptionId '' -TenantId ''
    }
    catch {
        if ($_.Exception.Message -notlike '*Set AZURE_SUBSCRIPTION_ID*') { throw }
        $missingContextRejected = $true
    }
    Assert-Equal $missingContextRejected $true

    $parameters.parameters.resourceNameSuffix.value = 'Invalid_Suffix'
    $parameters | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $temporaryParameters
    $invalidSuffixRejected = $false
    try {
        & $deploymentScript -Mode Validate -ParametersFile $temporaryParameters -SubscriptionId $subscription -TenantId $tenant
    }
    catch {
        if ($_.Exception.Message -notlike '*resource name suffix must be*') { throw }
        $invalidSuffixRejected = $true
    }
    Assert-Equal $invalidSuffixRejected $true
    Write-Output 'PASS: default/custom resource naming, missing account context, and invalid suffix checks.'
}
finally {
    if (Test-Path -LiteralPath $temporaryParameters) {
        Remove-Item -LiteralPath $temporaryParameters
    }
}

[CmdletBinding()]
param(
    [ValidateSet('Validate', 'WhatIf', 'Deploy')]
    [string]$Mode = 'Validate',
    [string]$SubscriptionId = '7ee7fa4f-8359-4fb9-ac34-361728102038',
    [string]$TenantId = '53fa074c-6e61-4c96-b167-fd879039b24e',
    [string]$Location = 'swedencentral',
    [string]$AppAdminEmail = $env:APP_ADMIN_EMAIL,
    [string]$AppAdminDisplayName = $(if ($env:APP_ADMIN_DISPLAY_NAME) { $env:APP_ADMIN_DISPLAY_NAME } else { 'Administrator' }),
    [ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9._-]{0,127}$')]
    [string]$ImageTag = (Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$infraRoot = $PSScriptRoot
$workspaceRoot = Split-Path -Parent $infraRoot
$templateFile = Join-Path $infraRoot 'main.bicep'
$parametersFile = Join-Path $infraRoot 'main.parameters.json'
$resourceGroupName = 'rg-dbmigratio-dev-1fa1'
$containerRegistryName = 'crdbmigratiodev1fa1'
$keyVaultName = 'kv-dbmigratio-dev-1fa1'
$sessionTag = '1fa1'
$placeholderImage = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

function Assert-Command {
    param([Parameter(Mandatory)][string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' is not installed or not available on PATH."
    }
}

function Invoke-AzText {
    param([Parameter(Mandatory)][string[]]$Arguments)

    $output = & az @Arguments --only-show-errors -o tsv
    if ($LASTEXITCODE -ne 0) {
        throw 'Azure CLI command failed.'
    }

    return ($output | Out-String).Trim()
}

function Invoke-AzJson {
    param([Parameter(Mandatory)][string[]]$Arguments)

    $output = & az @Arguments --only-show-errors -o json
    if ($LASTEXITCODE -ne 0) {
        throw 'Azure CLI command failed.'
    }

    $text = ($output | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    return $text | ConvertFrom-Json
}

function New-StrongPassword {
    $bytes = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(48)
    $random = [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', 'A').Replace('/', 'b')
    return ConvertTo-SecureString "Aa1-$random" -AsPlainText -Force
}

function New-ServiceToken {
    $bytes = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32)
    return ConvertTo-SecureString ([Convert]::ToBase64String($bytes)) -AsPlainText -Force
}

function Get-WorkerServiceToken {
    $null = & az keyvault show --name $keyVaultName --resource-group $resourceGroupName --only-show-errors -o none 2>$null
    if ($LASTEXITCODE -eq 0) {
        $value = & az keyvault secret show `
            --vault-name $keyVaultName `
            --name 'worker-service-token' `
            --query value `
            --only-show-errors `
            -o tsv 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(($value | Out-String))) {
            return ConvertTo-SecureString (($value | Out-String).Trim()) -AsPlainText -Force
        }
    }

    return New-ServiceToken
}

function Get-PostgresPassword {
    $null = & az keyvault show --name $keyVaultName --resource-group $resourceGroupName --only-show-errors -o none 2>$null
    if ($LASTEXITCODE -eq 0) {
        $value = & az keyvault secret show `
            --vault-name $keyVaultName `
            --name 'postgres-admin-password' `
            --query value `
            --only-show-errors `
            -o tsv 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(($value | Out-String))) {
            return ConvertTo-SecureString (($value | Out-String).Trim()) -AsPlainText -Force
        }
    }

    return New-StrongPassword
}

function Get-AppAdminPassword {
    $null = & az keyvault show --name $keyVaultName --resource-group $resourceGroupName --only-show-errors -o none 2>$null
    if ($LASTEXITCODE -eq 0) {
        $value = & az keyvault secret show `
            --vault-name $keyVaultName `
            --name 'app-admin-password' `
            --query value `
            --only-show-errors `
            -o tsv 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(($value | Out-String))) {
            return ConvertTo-SecureString (($value | Out-String).Trim()) -AsPlainText -Force
        }
    }

    if ([string]::IsNullOrWhiteSpace($env:APP_ADMIN_PASSWORD) -or $env:APP_ADMIN_PASSWORD.Length -lt 12) {
        throw 'Set APP_ADMIN_PASSWORD to at least 12 characters for the initial deployment.'
    }
    return ConvertTo-SecureString $env:APP_ADMIN_PASSWORD -AsPlainText -Force
}

function Invoke-SubscriptionDeployment {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][securestring]$PostgresPassword,
        [Parameter(Mandatory)][securestring]$AdminPassword,
        [Parameter(Mandatory)][securestring]$WorkerToken,
        [Parameter(Mandatory)][string]$DeployerObjectId,
        [Parameter(Mandatory)][bool]$ConfigureSecrets,
        [string]$ApiImage = $placeholderImage,
        [string]$WorkerImage = $placeholderImage,
        [string]$FrontendImage = $placeholderImage,
        [switch]$WhatIf
    )

    $plainPostgresPassword = [System.Net.NetworkCredential]::new('', $PostgresPassword).Password
    $plainAdminPassword = [System.Net.NetworkCredential]::new('', $AdminPassword).Password
    $plainWorkerToken = [System.Net.NetworkCredential]::new('', $WorkerToken).Password
    $command = if ($WhatIf) { 'what-if' } else { 'create' }
    $arguments = @(
        'deployment', 'sub', $command,
        '--name', $Name,
        '--location', $Location,
        '--template-file', $templateFile,
        '--parameters', "@$parametersFile",
        '--parameters',
        "deployerObjectId=$DeployerObjectId",
        "postgresAdminPassword=$plainPostgresPassword",
        "appAdminEmail=$AppAdminEmail",
        "appAdminPassword=$plainAdminPassword",
        "workerServiceToken=$plainWorkerToken",
        "appAdminDisplayName=$AppAdminDisplayName",
        "configureSecrets=$($ConfigureSecrets.ToString().ToLowerInvariant())",
        "apiContainerImage=$ApiImage",
        "workerContainerImage=$WorkerImage",
        "frontendContainerImage=$FrontendImage"
    )

    if ($WhatIf) {
        & az @arguments --only-show-errors
        if ($LASTEXITCODE -ne 0) {
            throw 'Azure subscription deployment What-If failed.'
        }
        return $null
    }

    return Invoke-AzJson -Arguments $arguments
}

function Push-RunningLocalImages {
    param([Parameter(Mandatory)][string]$LoginServer)

    $images = @(
        @{ Name = 'dbmigrationready-api'; Service = 'api' },
        @{ Name = 'dbmigrationready-worker'; Service = 'worker' },
        @{ Name = 'dbmigrationready-frontend'; Service = 'frontend' },
        @{ Name = 'dbmigrationready-discovery-agent'; Service = 'local-agent' }
    )

    $null = Invoke-AzText -Arguments @('acr', 'login', '--name', $containerRegistryName)
    $result = @{}
    foreach ($image in $images) {
        $containerId = & docker compose `
            --project-directory $workspaceRoot `
            --file (Join-Path $workspaceRoot 'docker-compose.yml') `
            ps --status running --quiet $image.Service
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($containerId | Out-String))) {
            throw "Local Compose service '$($image.Service)' must be running before deployment."
        }

        $localImageId = & docker inspect --format '{{.Image}}' (($containerId | Out-String).Trim())
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($localImageId | Out-String))) {
            throw "Could not resolve the running image for local Compose service '$($image.Service)'."
        }

        $tag = "$LoginServer/$($image.Name):$ImageTag"
        & docker tag (($localImageId | Out-String).Trim()) $tag
        if ($LASTEXITCODE -ne 0) {
            throw "Docker tag failed for $($image.Name)."
        }
        & docker push $tag | Out-Host
        if ($LASTEXITCODE -ne 0) {
            throw "Docker push failed for $($image.Name)."
        }
        $result[$image.Name] = $tag
    }

    return $result
}

Assert-Command -Name 'az'
Assert-Command -Name 'docker'

$null = & az version --only-show-errors -o json
if ($LASTEXITCODE -ne 0) {
    throw 'Azure CLI version verification failed.'
}
$null = & az bicep version
if ($LASTEXITCODE -ne 0) {
    throw 'Azure Bicep CLI verification failed.'
}
$null = & docker version --format '{{.Client.Version}}'
if ($LASTEXITCODE -ne 0) {
    throw 'Docker CLI is installed but unavailable.'
}

$account = Invoke-AzJson -Arguments @('account', 'show')
if ($account.tenantId -ne $TenantId) {
    throw "Azure CLI is signed into tenant '$($account.tenantId)', expected '$TenantId'."
}
if ($account.id -ne $SubscriptionId) {
    $null = Invoke-AzText -Arguments @('account', 'set', '--subscription', $SubscriptionId)
    $account = Invoke-AzJson -Arguments @('account', 'show')
}
if ($account.id -ne $SubscriptionId -or $account.tenantId -ne $TenantId) {
    throw 'Azure subscription or tenant verification failed.'
}

& az bicep build --file $templateFile --stdout | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw 'Bicep compilation failed.'
}

if ($Mode -eq 'Validate') {
    Write-Output 'Validation succeeded: prerequisites, Azure context, Docker CLI, and Bicep syntax are valid.'
    return
}

$deployerObjectId = Invoke-AzText -Arguments @('ad', 'signed-in-user', 'show', '--query', 'id')
$postgresPassword = Get-PostgresPassword
if ([string]::IsNullOrWhiteSpace($AppAdminEmail)) {
    throw 'Set APP_ADMIN_EMAIL or pass -AppAdminEmail.'
}
$appAdminPassword = Get-AppAdminPassword
$workerServiceToken = Get-WorkerServiceToken

if ($Mode -eq 'WhatIf') {
    $null = Invoke-SubscriptionDeployment `
        -Name "dbmigrationready-$sessionTag-whatif" `
        -PostgresPassword $postgresPassword `
        -AdminPassword $appAdminPassword `
        -WorkerToken $workerServiceToken `
        -DeployerObjectId $deployerObjectId `
        -ConfigureSecrets $false `
        -WhatIf
    Write-Output 'What-If completed without creating Azure resources.'
    return
}

$null = & docker info --format '{{.ServerVersion}}'
if ($LASTEXITCODE -ne 0) {
    throw 'Docker engine is not available for image build and push.'
}

$phaseOne = Invoke-SubscriptionDeployment `
    -Name "dbmigrationready-$sessionTag-phase1" `
    -PostgresPassword $postgresPassword `
    -AdminPassword $appAdminPassword `
    -WorkerToken $workerServiceToken `
    -DeployerObjectId $deployerObjectId `
    -ConfigureSecrets $false

$loginServer = $phaseOne.properties.outputs.containerRegistryLoginServer.value
$images = Push-RunningLocalImages -LoginServer $loginServer

$phaseTwo = Invoke-SubscriptionDeployment `
    -Name "dbmigrationready-$sessionTag-phase2" `
    -PostgresPassword $postgresPassword `
    -AdminPassword $appAdminPassword `
    -WorkerToken $workerServiceToken `
    -DeployerObjectId $deployerObjectId `
    -ConfigureSecrets $true `
    -ApiImage $images['dbmigrationready-api'] `
    -WorkerImage $images['dbmigrationready-worker'] `
    -FrontendImage $images['dbmigrationready-frontend']

$frontendUrl = $phaseTwo.properties.outputs.frontendUrl.value

[pscustomobject]@{
    ResourceGroup = $phaseTwo.properties.outputs.resourceGroupName.value
    ApiUrl = $phaseTwo.properties.outputs.apiUrl.value
    FrontendUrl = $frontendUrl
    ContainerRegistry = $phaseTwo.properties.outputs.containerRegistryLoginServer.value
    DiscoveryAgentImage = $images['dbmigrationready-discovery-agent']
} | Format-List
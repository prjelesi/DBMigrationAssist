[CmdletBinding()]
param(
    [ValidateSet('Validate', 'WhatIf', 'Deploy', 'DeployPhase2', 'ReleaseImages')]
    [string]$Mode = 'Validate',
    [string]$SubscriptionId = $env:AZURE_SUBSCRIPTION_ID,
    [string]$TenantId = $env:AZURE_TENANT_ID,
    [string]$ParametersFile = $(if (Test-Path (Join-Path $PSScriptRoot 'main.parameters.local.json')) {
        Join-Path $PSScriptRoot 'main.parameters.local.json'
    } else {
        Join-Path $PSScriptRoot 'main.parameters.json'
    }),
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
$parametersFile = (Resolve-Path -LiteralPath $ParametersFile).Path
if ([string]::IsNullOrWhiteSpace($SubscriptionId) -or [string]::IsNullOrWhiteSpace($TenantId)) {
    throw 'Set AZURE_SUBSCRIPTION_ID and AZURE_TENANT_ID, or pass -SubscriptionId and -TenantId explicitly.'
}
$deploymentParameters = Get-Content -LiteralPath $parametersFile -Raw | ConvertFrom-Json
$resourceNameSuffix = [string]$deploymentParameters.parameters.environmentName.value
if ($deploymentParameters.parameters.PSObject.Properties['resourceNameSuffix']) {
    $resourceNameSuffix = [string]$deploymentParameters.parameters.resourceNameSuffix.value
}
if ($resourceNameSuffix -cnotmatch '^[a-z0-9][a-z0-9-]{1,18}[a-z0-9]$') {
    throw 'The resource name suffix must be 3-20 lowercase letters, digits, or hyphens, and start and end with a letter or digit.'
}
$resourceGroupName = "rg-$resourceNameSuffix"
$containerRegistryName = "cr$($resourceNameSuffix.Replace('-', ''))"
$keyVaultName = "kv-$resourceNameSuffix"
$sessionTag = $resourceNameSuffix
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
        [string]$DiscoveryAgentImage = $placeholderImage,
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
        "frontendContainerImage=$FrontendImage",
        "discoveryAgentContainerImage=$DiscoveryAgentImage"
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

        $immutableTag = "$LoginServer/$($image.Name):$ImageTag"
        $latestTag = "$LoginServer/$($image.Name):latest"
        foreach ($tag in @($immutableTag, $latestTag)) {
            & docker tag (($localImageId | Out-String).Trim()) $tag
            if ($LASTEXITCODE -ne 0) {
                throw "Docker tag failed for $tag."
            }
            & docker push $tag | Out-Host
            if ($LASTEXITCODE -ne 0) {
                throw "Docker push failed for $tag."
            }
        }
        $result[$image.Name] = $immutableTag
    }

    return $result
}

function Build-ReleaseImages {
    & (Join-Path $workspaceRoot 'build.ps1')
    if ($LASTEXITCODE -ne 0) {
        throw 'Application release build failed.'
    }

    & docker compose `
        --project-directory $workspaceRoot `
        --file (Join-Path $workspaceRoot 'docker-compose.yml') `
        build api worker frontend local-agent
    if ($LASTEXITCODE -ne 0) {
        throw 'Docker image build failed.'
    }

    & docker compose `
        --project-directory $workspaceRoot `
        --file (Join-Path $workspaceRoot 'docker-compose.yml') `
        up -d --no-deps --force-recreate api worker frontend local-agent
    if ($LASTEXITCODE -ne 0) {
        throw 'Local release containers failed to start.'
    }
}

function Update-ContainerAppImages {
    param(
        [Parameter(Mandatory)][hashtable]$Images
    )

    $apps = @(
        @{ Name = "ca-api-$resourceNameSuffix"; Image = $Images['dbmigrationready-api'] },
        @{ Name = "ca-worker-$resourceNameSuffix"; Image = $Images['dbmigrationready-worker'] },
        @{ Name = "ca-agent-$resourceNameSuffix"; Image = $Images['dbmigrationready-discovery-agent'] },
        @{ Name = "ca-web-$resourceNameSuffix"; Image = $Images['dbmigrationready-frontend'] }
    )

    foreach ($app in $apps) {
        $null = Invoke-AzJson -Arguments @(
            'containerapp', 'update',
            '--name', $app.Name,
            '--resource-group', $resourceGroupName,
            '--image', $app.Image
        )

        $state = Invoke-AzJson -Arguments @(
            'containerapp', 'show',
            '--name', $app.Name,
            '--resource-group', $resourceGroupName,
            '--query', '{name:name,provisioningState:properties.provisioningState,latestRevision:properties.latestRevisionName,image:properties.template.containers[0].image}'
        )
        if ($state.provisioningState -ne 'Succeeded' -or $state.image -ne $app.Image) {
            throw "Container App '$($app.Name)' did not reach the expected image and provisioning state."
        }
        $state
    }
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

if ($Mode -eq 'ReleaseImages') {
    $null = & docker info --format '{{.ServerVersion}}'
    if ($LASTEXITCODE -ne 0) {
        throw 'Docker engine is not available for image build and push.'
    }

    Build-ReleaseImages
    $loginServer = Invoke-AzText -Arguments @('acr', 'show', '--name', $containerRegistryName, '--query', 'loginServer')
    $images = Push-RunningLocalImages -LoginServer $loginServer
    $states = Update-ContainerAppImages -Images $images

    $apiFqdn = Invoke-AzText -Arguments @(
        'containerapp', 'show', '--name', "ca-api-$resourceNameSuffix",
        '--resource-group', $resourceGroupName, '--query', 'properties.configuration.ingress.fqdn'
    )
    $frontendFqdn = Invoke-AzText -Arguments @(
        'containerapp', 'show', '--name', "ca-web-$resourceNameSuffix",
        '--resource-group', $resourceGroupName, '--query', 'properties.configuration.ingress.fqdn'
    )
    $apiUrl = "https://$apiFqdn/health"
    $frontendUrl = "https://$frontendFqdn/"
    if ((Invoke-WebRequest -Uri $apiUrl -UseBasicParsing).StatusCode -ne 200) {
        throw "API health verification failed at $apiUrl."
    }
    if ((Invoke-WebRequest -Uri $frontendUrl -UseBasicParsing).StatusCode -ne 200) {
        throw "Frontend verification failed at $frontendUrl."
    }

    [pscustomobject]@{
        ImageTag = $ImageTag
        LatestTagPublished = $true
        InfrastructureRedeployed = $false
        ApiHealthUrl = $apiUrl
        FrontendUrl = $frontendUrl
        ContainerApps = $states
    } | Format-List
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

if ($Mode -eq 'DeployPhase2') {
    $loginServer = Invoke-AzText -Arguments @('acr', 'show', '--name', $containerRegistryName, '--query', 'loginServer')
    $images = @{
        'dbmigrationready-api' = "$loginServer/dbmigrationready-api:$ImageTag"
        'dbmigrationready-worker' = "$loginServer/dbmigrationready-worker:$ImageTag"
        'dbmigrationready-frontend' = "$loginServer/dbmigrationready-frontend:$ImageTag"
        'dbmigrationready-discovery-agent' = "$loginServer/dbmigrationready-discovery-agent:$ImageTag"
    }

    $phaseTwo = Invoke-SubscriptionDeployment `
        -Name "dbmigrationready-$sessionTag-phase2" `
        -PostgresPassword $postgresPassword `
        -AdminPassword $appAdminPassword `
        -WorkerToken $workerServiceToken `
        -DeployerObjectId $deployerObjectId `
        -ConfigureSecrets $true `
        -ApiImage $images['dbmigrationready-api'] `
        -WorkerImage $images['dbmigrationready-worker'] `
        -FrontendImage $images['dbmigrationready-frontend'] `
        -DiscoveryAgentImage $images['dbmigrationready-discovery-agent']

    [pscustomobject]@{
        ResourceGroup = $phaseTwo.properties.outputs.resourceGroupName.value
        ApiUrl = $phaseTwo.properties.outputs.apiUrl.value
        FrontendUrl = $phaseTwo.properties.outputs.frontendUrl.value
        ContainerRegistry = $phaseTwo.properties.outputs.containerRegistryLoginServer.value
        DiscoveryAgentImage = $images['dbmigrationready-discovery-agent']
    } | Format-List
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
    -FrontendImage $images['dbmigrationready-frontend'] `
    -DiscoveryAgentImage $images['dbmigrationready-discovery-agent']

$frontendUrl = $phaseTwo.properties.outputs.frontendUrl.value

[pscustomobject]@{
    ResourceGroup = $phaseTwo.properties.outputs.resourceGroupName.value
    ApiUrl = $phaseTwo.properties.outputs.apiUrl.value
    FrontendUrl = $frontendUrl
    ContainerRegistry = $phaseTwo.properties.outputs.containerRegistryLoginServer.value
    DiscoveryAgentImage = $images['dbmigrationready-discovery-agent']
} | Format-List
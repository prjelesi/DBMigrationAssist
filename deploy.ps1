#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Build the assessment engine container and deploy it.
    Supports two deployment targets:
      -Target Local   : Build and run via Docker Compose
      -Target Azure   : Build, push to ACR, deploy to Azure Container Apps

.PARAMETER Target
    Deployment target: 'Local' or 'Azure'

.PARAMETER SubscriptionId
    Azure subscription ID (Azure target only)

.PARAMETER ResourceGroup
    Azure resource group (Azure target only)

.PARAMETER ApiKey
    API key for the assessment engine

.PARAMETER Tag
    Docker image tag (default: latest)

.PARAMETER SkipBuild
    Skip Docker build (use existing local image)

.EXAMPLE
    # Local Docker
    .\deploy.ps1 -Target Local

    # Azure Container Apps
    .\deploy.ps1 -Target Azure -ApiKey "my-strong-key"
#>
param(
    [ValidateSet("Local", "Azure")]
    [string]$Target = "Local",

    [string]$SubscriptionId = "7ee7fa4f-8359-4fb9-ac34-361728102038",
    [string]$ResourceGroup  = "rg-dbmigration-demo",
    [string]$Location       = "westeurope",
    [string]$ApiKey         = "",
    [string]$Tag            = "latest",
    [switch]$SkipBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot

function Write-Step { param([string]$Msg) Write-Host "`n>> $Msg" -ForegroundColor Cyan }
function Write-OK   { param([string]$Msg) Write-Host "   [OK] $Msg" -ForegroundColor Green }
function Write-Info { param([string]$Msg) Write-Host "   [..] $Msg" -ForegroundColor Gray }

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Docker not found. Install Docker Desktop from https://www.docker.com/products/docker-desktop"
}

# ── Get API key ───────────────────────────────────────────────────────────────
if (-not $ApiKey) {
    if (Test-Path (Join-Path $Root "docker\.env")) {
        $envContent = Get-Content (Join-Path $Root "docker\.env")
        $ApiKey = ($envContent | Where-Object { $_ -match "^API_KEY=" }) -replace "^API_KEY=", ""
    }
    if (-not $ApiKey) {
        $ApiKey = Read-Host "Enter API key for the assessment engine"
    }
}

# ═════════════════════════════════════════════════════════════════════════════
# LOCAL TARGET
# ═════════════════════════════════════════════════════════════════════════════
if ($Target -eq "Local") {
    Write-Step "Building and starting local Docker container"

    # Ensure .env exists
    $envFile = Join-Path $Root "docker\.env"
    if (-not (Test-Path $envFile)) {
        Copy-Item (Join-Path $Root "docker\.env.example") $envFile
        (Get-Content $envFile) -replace "^API_KEY=.*", "API_KEY=$ApiKey" | Set-Content $envFile
        Write-OK "Created docker/.env"
    }

    if (-not $SkipBuild) {
        Write-Step "Building Docker image (this takes ~5 min first time)"
        docker build `
            -f (Join-Path $Root "docker\Dockerfile") `
            -t "db-migration-assessment:$Tag" `
            $Root
        Write-OK "Image built: db-migration-assessment:$Tag"
    }

    Write-Step "Starting container"
    Push-Location (Join-Path $Root "docker")
    docker compose up -d
    Pop-Location

    # Wait for health
    $maxWait = 60; $elapsed = 0; $healthy = $false
    Write-Info "Waiting for container to be healthy..."
    while (-not $healthy -and $elapsed -lt $maxWait) {
        Start-Sleep -Seconds 3; $elapsed += 3
        try {
            $r = Invoke-RestMethod "http://localhost:8000/health" -TimeoutSec 2 -ErrorAction Stop
            if ($r.status -eq "ok") { $healthy = $true }
        } catch {}
    }

    if ($healthy) {
        Write-OK "Container healthy"
        Write-Host ""
        Write-Host "  API URL  : http://localhost:8000"      -ForegroundColor Green
        Write-Host "  API Docs : http://localhost:8000/docs" -ForegroundColor Green
        Write-Host "  Health   : http://localhost:8000/health" -ForegroundColor Green
        Write-Host ""
        Write-Host "  Quick test:"
        Write-Host "  curl -H 'X-API-Key: $ApiKey' http://localhost:8000/health"
    } else {
        Write-Host "[WARN] Container may still be starting. Check: docker logs db-migration-assessment" -ForegroundColor Yellow
    }
    return
}

# ═════════════════════════════════════════════════════════════════════════════
# AZURE TARGET
# ═════════════════════════════════════════════════════════════════════════════
Write-Step "Deploying to Azure Container Apps"

# ── Deploy infrastructure (ACR + ACA) ─────────────────────────────────────────
Write-Step "Deploying Azure infrastructure (ACR + Container Apps)"
$infraOut = az deployment group create `
    --name "aca-deploy-$(Get-Date -Format 'HHmmss')" `
    --resource-group $ResourceGroup `
    --subscription $SubscriptionId `
    --template-file (Join-Path $Root "infrastructure\main.bicep") `
    --parameters `
        "apiKey=$ApiKey" `
        existingVnetName=vnet-demo `
        existingSubnetName=subnet-demo `
    --query properties.outputs -o json | ConvertFrom-Json

if ($LASTEXITCODE -ne 0) { throw "Infrastructure deployment failed" }

$acrServer = $infraOut.acrLoginServer.value
$acrName   = $infraOut.acrName.value
$apiUrl    = $infraOut.apiUrl.value

Write-OK "ACR: $acrServer"
Write-OK "API: $apiUrl"

# ── Build Docker image ────────────────────────────────────────────────────────
if (-not $SkipBuild) {
    Write-Step "Building Docker image"
    docker build `
        -f (Join-Path $Root "docker\Dockerfile") `
        -t "${acrServer}/db-migration-assessment:${Tag}" `
        $Root
    Write-OK "Image built"
}

# ── Push to ACR ───────────────────────────────────────────────────────────────
Write-Step "Pushing image to ACR: $acrServer"
$acrCreds = az acr credential show --name $acrName --subscription $SubscriptionId -o json | ConvertFrom-Json
docker login $acrServer -u $acrCreds.username -p $acrCreds.passwords[0].value
docker push "${acrServer}/db-migration-assessment:${Tag}"
Write-OK "Image pushed"

# ── Update Container App with new image ───────────────────────────────────────
Write-Step "Updating Container App"
$appName = "dbmigassess-app"
az containerapp update `
    --name $appName `
    --resource-group $ResourceGroup `
    --subscription $SubscriptionId `
    --image "${acrServer}/db-migration-assessment:${Tag}" `
    -o none
Write-OK "Container App updated"

# ── Verify ────────────────────────────────────────────────────────────────────
Write-Step "Verifying deployment"
Start-Sleep -Seconds 15
try {
    $health = Invoke-RestMethod "$apiUrl/health" -TimeoutSec 15 -ErrorAction Stop
    Write-OK "Health check passed: $($health.status) v$($health.version)"
} catch {
    Write-Host "[WARN] Health check timed out — container may still be starting" -ForegroundColor Yellow
}

$separator = "=" * 65
Write-Host ""
Write-Host $separator -ForegroundColor Green
Write-Host "  AZURE DEPLOYMENT COMPLETE" -ForegroundColor Green
Write-Host $separator -ForegroundColor Green
Write-Host "  API URL  : $apiUrl"
Write-Host "  API Docs : $apiUrl/docs"
Write-Host "  Health   : $apiUrl/health"
Write-Host ""
Write-Host "  Quick test:"
Write-Host "  curl -H 'X-API-Key: $ApiKey' $apiUrl/health"
Write-Host $separator -ForegroundColor Green

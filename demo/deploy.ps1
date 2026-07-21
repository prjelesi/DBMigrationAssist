#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Deploy the DBMigrationAssist demo environment to Azure.
    Creates all source database types (SQL Server, PostgreSQL, MySQL, MariaDB, MongoDB, Cassandra)
    on a single Azure VM for demo and testing purposes.

.PARAMETER SubscriptionId
    Azure subscription ID (default: 7ee7fa4f-8359-4fb9-ac34-361728102038)

.PARAMETER ResourceGroup
    Resource group name (created if it doesn't exist)

.PARAMETER Location
    Azure region

.PARAMETER AdminPassword
    VM admin password (must meet Azure complexity requirements)

.PARAMETER AllowMyIp
    Restrict NSG to your current public IP (recommended). Set to $false to allow all IPs.

.PARAMETER Destroy
    Tear down the demo environment (deletes the resource group)

.EXAMPLE
    .\deploy.ps1 -AdminPassword "MySecureP@ss123"
    .\deploy.ps1 -Destroy
#>

param(
    [string]$SubscriptionId = "7ee7fa4f-8359-4fb9-ac34-361728102038",
    [string]$ResourceGroup  = "rg-dbmigration-demo",
    [string]$Location       = "westeurope",
    [string]$AdminPassword  = "",
    [switch]$AllowMyIp      = $true,
    [switch]$Destroy
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ScriptDir = $PSScriptRoot

function Write-Step { param([string]$Msg) Write-Host "`n>> $Msg" -ForegroundColor Cyan }
function Write-OK   { param([string]$Msg) Write-Host "   [OK] $Msg" -ForegroundColor Green }
function Write-Info { param([string]$Msg) Write-Host "   [..] $Msg" -ForegroundColor Gray }

# ── Destroy mode ──────────────────────────────────────────────────────────────
if ($Destroy) {
    Write-Step "Destroying demo environment"
    $confirm = Read-Host "This will delete resource group '$ResourceGroup' and ALL resources in it. Type 'yes' to confirm"
    if ($confirm -ne 'yes') { Write-Host "Cancelled."; exit 0 }
    az group delete --name $ResourceGroup --subscription $SubscriptionId --yes --no-wait
    Write-OK "Deletion initiated (runs in background ~5 minutes)"
    exit 0
}

# ── Check prerequisites ───────────────────────────────────────────────────────
Write-Step "Checking prerequisites"
if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw "Azure CLI not found. Install from https://aka.ms/installazurecliwindows" }

$account = az account show --query "{sub:id,name:name}" -o json | ConvertFrom-Json
Write-OK "Logged in as subscription: $($account.name) ($($account.sub))"

if ($account.sub -ne $SubscriptionId) {
    Write-Info "Switching to subscription $SubscriptionId"
    az account set --subscription $SubscriptionId
}

# ── Get password ──────────────────────────────────────────────────────────────
if (-not $AdminPassword) {
    $secure = Read-Host "Enter VM admin password (min 12 chars, upper+lower+number+symbol)" -AsSecureString
    $AdminPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    )
}

# ── Get my public IP for NSG ──────────────────────────────────────────────────
$sourceIp = "*"
if ($AllowMyIp) {
    Write-Info "Detecting your public IP..."
    try {
        $sourceIp = (Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 5).Trim()
        Write-OK "NSG will allow access from: $sourceIp"
    } catch {
        Write-Warning "Could not detect public IP — NSG will allow all IPs (*)"
    }
}

# ── Create resource group ─────────────────────────────────────────────────────
Write-Step "Creating resource group: $ResourceGroup ($Location)"
az group create `
    --name $ResourceGroup `
    --location $Location `
    --subscription $SubscriptionId `
    --tags Project=DBMigrationAssist Environment=Demo CreatedBy=DeployScript `
    -o none
Write-OK "Resource group ready"

# ── Deploy Bicep ──────────────────────────────────────────────────────────────
Write-Step "Deploying Azure VM with all demo databases (takes ~5 minutes)"
Write-Info "VM size: Standard_D4s_v3 | OS: Ubuntu 22.04"
Write-Info "Databases: SQL Server 2019, PostgreSQL 14, MySQL 8, MariaDB 10.11, MongoDB 6, Cassandra 4.1"

$deployResult = az deployment group create `
    --name "demo-deploy-$(Get-Date -Format 'yyyyMMdd-HHmmss')" `
    --resource-group $ResourceGroup `
    --subscription $SubscriptionId `
    --template-file (Join-Path $ScriptDir "bicep\main.bicep") `
    --parameters `
        location=$Location `
        adminUsername=demoadmin `
        adminPassword=$AdminPassword `
        allowedSourceIp=$sourceIp `
        vmSize=Standard_D4s_v3 `
    --query "properties.outputs" -o json | ConvertFrom-Json

if ($LASTEXITCODE -ne 0) { throw "Deployment failed" }

$vmFqdn  = $deployResult.vmFqdn.value
$vmIp    = $deployResult.vmPublicIp.value
$sshCmd  = $deployResult.sshCommand.value

Write-OK "VM deployed: $vmFqdn ($vmIp)"

# ── Wait for cloud-init to finish ─────────────────────────────────────────────
Write-Step "Waiting for database containers to start (cloud-init takes ~5-8 min after VM boots)"
Write-Info "You can monitor progress via: ssh demoadmin@$vmFqdn 'tail -f /var/log/cloud-init-output.log'"

$ready = $false
$maxWait = 600  # 10 minutes
$elapsed = 0
while (-not $ready -and $elapsed -lt $maxWait) {
    Start-Sleep -Seconds 20
    $elapsed += 20
    Write-Host "   Waiting... ($elapsed/${maxWait}s)" -NoNewline
    Write-Host "`r" -NoNewline
}

# ── Update demo inventory CSV ─────────────────────────────────────────────────
Write-Step "Generating demo inventory CSV"
$inventoryCsv = Join-Path $ScriptDir "..\input\demo-db-inventory.csv"

$csvContent = @"
DatabaseName,SourceType,SourceVersion,SourceEnvironment,TargetType,MaxDowntime,Connectivity,LandingZone,DataSize,StoredProcs,Dependencies,SpecialFeatures,TeamSkill,RollbackPlan,DatabaseCount,HostName,Port
DemoDB_SQLServer,SQL Server,2019,OnPrem,Azure SQL Managed Instance,hours,internet,no,small,few,,,moderate,yes_untested,1,$vmFqdn,1433
DemoDB_PostgreSQL,PostgreSQL,14,OnPrem,Azure Database for PostgreSQL Flexible Server,zero,internet,no,small,few,,,moderate,yes_untested,1,$vmFqdn,5432
DemoDB_MySQL,MySQL,8.0,OnPrem,Azure Database for MySQL Flexible Server,hours,internet,no,small,few,,,moderate,yes_untested,1,$vmFqdn,3306
DemoDB_MariaDB,MariaDB,10.11,OnPrem,Azure Database for MySQL Flexible Server,days,internet,no,small,none,,,beginner,partial,1,$vmFqdn,3307
DemoDB_MongoDB,MongoDB,6.0,OnPrem,Azure DocumentDB,hours,internet,no,small,none,,,moderate,yes_untested,1,$vmFqdn,27017
DemoDB_Cassandra,Cassandra,4.1,OnPrem,Azure Managed Instance for Apache Cassandra,days,internet,no,small,none,,,beginner,no,1,$vmFqdn,9042
"@

$csvContent | Set-Content $inventoryCsv -Encoding UTF8
Write-OK "Demo inventory written to: input\demo-db-inventory.csv"

# ── Print summary ─────────────────────────────────────────────────────────────
$separator = "=" * 70
Write-Host ""
Write-Host $separator -ForegroundColor Green
Write-Host "  DEMO ENVIRONMENT READY" -ForegroundColor Green
Write-Host $separator -ForegroundColor Green
Write-Host ""
Write-Host "  VM Public IP   : $vmIp"
Write-Host "  VM FQDN        : $vmFqdn"
Write-Host "  SSH            : $sshCmd"
Write-Host ""
Write-Host "  Connection strings:" -ForegroundColor Cyan
Write-Host "  SQL Server  : Server=$vmFqdn,1433;Database=DemoDB;User=sa;Password=Demo@Password123"
Write-Host "  PostgreSQL  : Host=$vmFqdn;Port=5432;Database=demodb;Username=demouser;Password=Demo@Password123"
Write-Host "  MySQL       : Server=$vmFqdn;Port=3306;Database=demodb;Uid=demouser;Pwd=Demo@Password123"
Write-Host "  MariaDB     : Server=$vmFqdn;Port=3307;Database=demodb;Uid=demouser;Pwd=Demo@Password123"
Write-Host "  MongoDB     : mongodb://demouser:Demo%40Password123@${vmFqdn}:27017/demodb"
Write-Host "  Cassandra   : $vmFqdn:9042 (keyspace: demodb)"
Write-Host ""
Write-Host "  Run assessment against demo DBs:" -ForegroundColor Cyan
Write-Host "  pwsh Invoke-Assessment.ps1 -InputFile input\demo-db-inventory.csv -OutputDir output\demo -SkipInfoGather"
Write-Host ""
Write-Host "  To destroy: pwsh demo\deploy.ps1 -Destroy"
Write-Host $separator -ForegroundColor Green

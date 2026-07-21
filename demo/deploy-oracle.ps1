#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Deploy Oracle XE 21c demo VM to Azure.
    Oracle XE 21c is the free developer edition — functionally equivalent
    to Oracle 19c/21c Enterprise for demo and factory script purposes.
    Limits: 2 CPU threads, 2GB RAM for Oracle, 12GB user data.

.NOTES
    Oracle XE 21c is free with no license required.
    For production Oracle 19c EE/SE2, a paid Oracle license is needed.

.PARAMETER SubscriptionId
    Azure subscription ID

.PARAMETER ResourceGroup
    Resource group (shared with main demo or separate)

.PARAMETER OracleSysPassword
    Password for Oracle SYS/SYSTEM accounts

.PARAMETER Destroy
    Remove the Oracle VM and its resources
#>
param(
    [string]$SubscriptionId  = "7ee7fa4f-8359-4fb9-ac34-361728102038",
    [string]$ResourceGroup   = "rg-dbmigration-demo",
    [string]$Location        = "westeurope",
    [string]$AdminPassword   = "",
    [string]$OracleSysPassword = "",
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
    Write-Step "Deleting Oracle VM resources"
    $confirm = Read-Host "Delete Oracle VM from '$ResourceGroup'? Type 'yes'"
    if ($confirm -ne 'yes') { exit 0 }
    az vm delete --name vm-demo-oracle --resource-group $ResourceGroup --subscription $SubscriptionId --yes --no-wait
    az network nic delete --name nic-demo-oracle --resource-group $ResourceGroup --subscription $SubscriptionId --no-wait
    Write-OK "Oracle VM deletion initiated"
    exit 0
}

# ── Passwords ─────────────────────────────────────────────────────────────────
if (-not $AdminPassword) {
    $s = Read-Host "VM admin password" -AsSecureString
    $AdminPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s))
}
if (-not $OracleSysPassword) {
    $s = Read-Host "Oracle SYS password (used for SYS, SYSTEM, PDBADMIN)" -AsSecureString
    $OracleSysPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s))
}

# ── My IP ─────────────────────────────────────────────────────────────────────
Write-Info "Detecting your public IP..."
$myIp = (Invoke-RestMethod "https://api.ipify.org").Trim()
Write-OK "NSG will allow: $myIp"

# ── Ensure resource group exists ──────────────────────────────────────────────
Write-Step "Ensuring resource group exists: $ResourceGroup"
az group create --name $ResourceGroup --location $Location `
    --subscription $SubscriptionId --tags Project=DBMigrationAssist Environment=Demo -o none
Write-OK "Resource group ready"

# ── Deploy Oracle VM ──────────────────────────────────────────────────────────
Write-Step "Deploying Oracle XE 21c VM (Oracle Linux 9 | Standard_D4s_v3)"
Write-Info "This deployment takes ~5 min. Oracle installs in background (~15-20 min after VM boots)"

$out = az deployment group create `
    --name "oracle-$(Get-Date -Format 'HHmmss')" `
    --resource-group $ResourceGroup `
    --subscription $SubscriptionId `
    --template-file (Join-Path $ScriptDir "bicep\oracle-vm.bicep") `
    --parameters `
        adminUsername=demoadmin `
        adminPassword=$AdminPassword `
        allowedSourceIp=$myIp `
        oracleSysPassword=$OracleSysPassword `
        existingVnetName=vnet-demo `
        existingSubnetName=subnet-demo `
    --query "properties.outputs" -o json | ConvertFrom-Json

if ($LASTEXITCODE -ne 0) { throw "Deployment failed" }

$fqdn      = $out.vmFqdn.value
$ip        = $out.vmPublicIp.value
$privateIp = $out.vmPrivateIp.value

Write-OK "Oracle VM deployed: $fqdn ($ip)"

# ── Update demo inventory CSV ─────────────────────────────────────────────────
Write-Step "Adding Oracle to demo inventory CSV"
$inventoryPath = Join-Path $ScriptDir "..\input\demo-db-inventory.csv"

# Remove existing Oracle row if any, then append
$existing = Get-Content $inventoryPath | Where-Object { $_ -notmatch '^DemoDB_Oracle' }
$oracleRow = "DemoDB_Oracle,Oracle,21c (XE),OnPrem,Azure Database for PostgreSQL Flexible Server,days,internet,no,small,extensive,,,beginner,no,1,$fqdn,1521"
($existing + $oracleRow) | Set-Content $inventoryPath -Encoding UTF8
Write-OK "Oracle row added to demo-db-inventory.csv"

# ── Summary ───────────────────────────────────────────────────────────────────
$sep = "=" * 65
Write-Host ""
Write-Host $sep -ForegroundColor Green
Write-Host "  ORACLE XE 21c VM DEPLOYED" -ForegroundColor Green
Write-Host $sep -ForegroundColor Green
Write-Host "  IP / FQDN   : $ip / $fqdn"
Write-Host "  Private IP  : $privateIp  (same VNet as other demo DBs: vnet-demo)"
Write-Host "  SSH         : ssh demoadmin@$fqdn"
Write-Host ""
Write-Host "  Oracle connection (after ~20 min install):" -ForegroundColor Cyan
Write-Host "  Service   : XEPDB1 (pluggable DB for demo user)"
Write-Host "  Demo user : demouser / Demo@Password123"
Write-Host "  SYS/SYSTEM: $OracleSysPassword"
Write-Host "  JDBC      : jdbc:oracle:thin:@//${fqdn}:1521/XEPDB1"
Write-Host "  SQLPlus   : sqlplus demouser/Demo@Password123@//${fqdn}:1521/XEPDB1"
Write-Host "  EM Express: https://${fqdn}:5500/em"
Write-Host ""
Write-Host "  Monitor install progress:" -ForegroundColor Cyan
Write-Host "  ssh demoadmin@$fqdn 'sudo tail -f /var/log/oracle-install.log'"
Write-Host ""
Write-Host "  Demo schema contains:" -ForegroundColor Cyan
Write-Host "  - EMPLOYEES table (with sequence)"
Write-Host "  - PRODUCTS table (with sequence + TIMESTAMP)"
Write-Host "  - V_ENGINEERING view"
Write-Host "  - EMP_PKG package (PL/SQL — tests heterogeneous complexity)"
Write-Host "  - TRG_EMP_AUDIT trigger"
Write-Host ""
Write-Host "  Assessment migration target: Oracle -> Azure PostgreSQL (AI Assisted)"
Write-Host "  Required: GitHub Copilot license + Azure OpenAI endpoint"
Write-Host $sep -ForegroundColor Green

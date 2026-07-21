#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Local development setup for DBMigrationAssist.
    Installs Python deps, creates .env, validates JSON data, runs a quick smoke test.

.PARAMETER SkipPython
    Skip Python dependency installation (use if already installed)

.PARAMETER SkipDocker
    Skip Docker build (use for pure local testing without container)
#>
param(
    [switch]$SkipPython,
    [switch]$SkipDocker
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot

function Write-Step { param([string]$Msg) Write-Host "`n>> $Msg" -ForegroundColor Cyan }
function Write-OK   { param([string]$Msg) Write-Host "   [OK] $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "   [!!] $Msg" -ForegroundColor Yellow }
function Write-Fail { param([string]$Msg) Write-Host "   [FAIL] $Msg" -ForegroundColor Red }

# ── 1. Prerequisites check ────────────────────────────────────────────────────
Write-Step "Checking prerequisites"

$checks = @(
    @{ Name = "PowerShell 7+"; Test = { $PSVersionTable.PSVersion.Major -ge 7 } },
    @{ Name = "Python 3.9+";   Test = { python --version 2>&1 | Select-String "3\.[9-9][0-9]*|3\.1[0-9]" } },
    @{ Name = "pip";           Test = { Get-Command pip -ErrorAction SilentlyContinue } },
    @{ Name = "Docker";        Test = { Get-Command docker -ErrorAction SilentlyContinue } }
)

$allOk = $true
foreach ($c in $checks) {
    if (& $c.Test) { Write-OK $c.Name }
    else {
        if ($c.Name -eq "Docker" -and $SkipDocker) { Write-Warn "Docker not found (skipped)" }
        else { Write-Fail "$($c.Name) not found"; $allOk = $false }
    }
}
if (-not $allOk) { throw "Missing prerequisites. Install them and re-run." }

# ── 2. Create .env for local dev ──────────────────────────────────────────────
Write-Step "Setting up local .env"
$envFile = Join-Path $Root "docker\.env"
if (-not (Test-Path $envFile)) {
    Copy-Item (Join-Path $Root "docker\.env.example") $envFile
    Write-OK "Created docker/.env from example — update with real values when needed"
} else {
    Write-OK "docker/.env already exists"
}

# Create a dev .env at root for running API locally (without Docker)
$localEnv = Join-Path $Root ".env"
if (-not (Test-Path $localEnv)) {
    @"
DATAVERSE_URL=
AZURE_CLIENT_ID=
AZURE_CLIENT_SECRET=
AZURE_TENANT_ID=
API_KEY=dev-local-key-change-me
CALLBACK_WEBHOOK_URL=
"@ | Set-Content $localEnv -Encoding UTF8
    Write-OK "Created .env for local API run (Dataverse disabled in dev)"
} else {
    Write-OK ".env already exists"
}

# ── 3. Python virtual environment ─────────────────────────────────────────────
Write-Step "Setting up Python virtual environment"
$venvPath = Join-Path $Root ".venv"
if (-not (Test-Path $venvPath)) {
    python -m venv $venvPath
    Write-OK "Created .venv"
} else {
    Write-OK ".venv already exists"
}

if (-not $SkipPython) {
    $pip = if ($IsWindows) { "$venvPath\Scripts\pip.exe" } else { "$venvPath/bin/pip" }
    & $pip install --quiet --upgrade pip
    & $pip install --quiet -r (Join-Path $Root "api\requirements.txt")
    & $pip install --quiet -r (Join-Path $Root "tests\requirements-test.txt")
    Write-OK "Python dependencies installed"
}

# ── 4. Validate data files ────────────────────────────────────────────────────
Write-Step "Validating JSON data files"
$dataFiles = @(
    "assessment-engine\data\migration-paths.json",
    "assessment-engine\data\questionnaire.json",
    "assessment-engine\data\scoring-matrix.json"
)
foreach ($f in $dataFiles) {
    $path = Join-Path $Root $f
    try {
        $parsed = Get-Content $path -Raw | ConvertFrom-Json
        $count = if ($f -like "*migration*") { "($($parsed.paths.Count) paths)" } else { "" }
        Write-OK "$f $count"
    } catch {
        throw "Invalid JSON in $f : $_"
    }
}

# ── 5. Smoke test: run assessment against sample CSV ─────────────────────────
Write-Step "Running assessment smoke test"
$python = if ($IsWindows) { "$venvPath\Scripts\python.exe" } else { "$venvPath/bin/python" }
$sampleCsv = Join-Path $Root "input\sample-db-inventory.csv"
$outDir    = Join-Path $Root "output\smoke-test"

& pwsh -NonInteractive -ExecutionPolicy Bypass `
       -File (Join-Path $Root "Invoke-Assessment.ps1") `
       -InputFile $sampleCsv `
       -OutputDir $outDir `
       -SkipInfoGather

$reports = Get-ChildItem $outDir -Filter "assessment-report-*.json" | Sort-Object Name -Descending
if ($reports.Count -eq 0) { throw "Smoke test failed — no report generated" }

$report = Get-Content $reports[0].FullName | ConvertFrom-Json
Write-OK "Assessment smoke test passed — $($report.Count) databases scored"
$report | ForEach-Object { Write-OK "  $($_.DatabaseName): $($_.ReadinessScore)/100 [$($_.ReadinessBand)]" }

# ── 6. Start API locally (background) ────────────────────────────────────────
Write-Step "Starting API server for local testing"
$uvicorn = if ($IsWindows) { "$venvPath\Scripts\uvicorn.exe" } else { "$venvPath/bin/uvicorn" }
Write-Host "   Run this command to start the API:"
Write-Host "   $uvicorn api.main:app --reload --host 0.0.0.0 --port 8000" -ForegroundColor Yellow
Write-Host ""
Write-Host "   Or run the integration tests directly:"
Write-Host "   $python -m pytest tests/ -v" -ForegroundColor Yellow

# ── 7. Docker build (optional) ────────────────────────────────────────────────
if (-not $SkipDocker) {
    Write-Step "Building Docker image"
    docker build -f docker/Dockerfile -t db-migration-assessment:dev . 2>&1 | Tail-Lines 10
    if ($LASTEXITCODE -eq 0) { Write-OK "Docker image built: db-migration-assessment:dev" }
    else { Write-Warn "Docker build had issues — check output above" }
}

Write-Host ""
Write-Host ("=" * 60) -ForegroundColor Green
Write-Host "  Setup complete! Next steps:" -ForegroundColor Green
Write-Host ("=" * 60) -ForegroundColor Green
Write-Host "  1. Start API:  $uvicorn api.main:app --reload"
Write-Host "  2. Run tests:  $python -m pytest tests/ -v"
Write-Host "  3. API docs:   http://localhost:8000/docs"
Write-Host ""

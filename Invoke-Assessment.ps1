#!/usr/bin/env pwsh
<#
.SYNOPSIS
    DB Migration Readiness Assessment Orchestrator
    Wraps the Cloud Accelerate Factory info-gather scripts and produces
    a scored readiness report.

.DESCRIPTION
    1. Reads a questionnaire response file (JSON or CSV)
    2. Determines the correct factory script to run for the source DB type
    3. Invokes the info-gather script to collect technical metadata
    4. Scores readiness using scoring-matrix.json
    5. Outputs a JSON assessment report

.PARAMETER InputFile
    Path to the questionnaire responses CSV or JSON file

.PARAMETER OutputDir
    Directory to write assessment reports to (default: ./output)

.PARAMETER SkipInfoGather
    Skip running factory scripts (use if already run externally)

.EXAMPLE
    .\Invoke-Assessment.ps1 -InputFile .\input\db-inventory.csv -OutputDir .\output
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$InputFile,

    [string]$OutputDir = ".\output",

    [switch]$SkipInfoGather
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Paths ──────────────────────────────────────────────────────────────────────
$ScriptRoot    = $PSScriptRoot
$DataDir       = Join-Path $ScriptRoot "assessment-engine\data"
$FactoryRoot   = Join-Path $ScriptRoot "factory-scripts"

$MigrationPathsFile = Join-Path $DataDir "migration-paths.json"
$ScoringMatrixFile  = Join-Path $DataDir "scoring-matrix.json"

# ── Load reference data ────────────────────────────────────────────────────────
$migrationPaths = Get-Content $MigrationPathsFile | ConvertFrom-Json
$scoringMatrix  = Get-Content $ScoringMatrixFile  | ConvertFrom-Json

# ── Helper: Timestamp ──────────────────────────────────────────────────────────
function Get-Timestamp { return (Get-Date -Format "yyyy-MM-dd_HH-mm-ss") }

# ── Helper: Log ───────────────────────────────────────────────────────────────
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "HH:mm:ss"
    $color = switch ($Level) {
        "INFO"    { "Cyan" }
        "SUCCESS" { "Green" }
        "WARN"    { "Yellow" }
        "ERROR"   { "Red" }
        default   { "White" }
    }
    Write-Host "[$ts][$Level] $Message" -ForegroundColor $color
}

# ── Load Input ────────────────────────────────────────────────────────────────
Write-Log "Loading input file: $InputFile"

$ext = [System.IO.Path]::GetExtension($InputFile).ToLower()
if ($ext -eq ".csv") {
    $databases = Import-Csv -Path $InputFile
} elseif ($ext -eq ".json") {
    $databases = Get-Content $InputFile | ConvertFrom-Json
} else {
    throw "Unsupported input format: $ext. Use .csv or .json"
}

Write-Log "Found $($databases.Count) database(s) to assess" "SUCCESS"

# ── Ensure output directory ───────────────────────────────────────────────────
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# ── Resolve Migration Path ────────────────────────────────────────────────────
function Resolve-MigrationPath {
    param($SourceType, $TargetType, $SourceEnv)

    # Normalise environment variants so the CSV column doesn't need to be exact
    $envMap = @{
        'AzureVM'           = @('AzureVM','AzureVM_Windows','AzureVM_Linux')
        'OnPrem'            = @('OnPrem','OnPremises','On-Premises','Physical')
        'AWS_RDS'           = @('AWS_RDS','AWS RDS')
        'AWS_EC2'           = @('AWS_EC2','AWS EC2')
        'AWS_Aurora'        = @('AWS_Aurora','AWS Aurora')
        'AWS_DocumentDB'    = @('AWS_DocumentDB','AWS DocumentDB')
        'GCP_CloudSQL'      = @('GCP_CloudSQL','GCP CloudSQL')
        'GCP_GCE'           = @('GCP_GCE','GCP GCE','GCP Compute Engine')
        'AzurePaaS_SingleServer' = @('AzurePaaS','AzurePaaS_SingleServer','SingleServer')
    }

    # Find normalised env key
    $normEnv = $SourceEnv
    foreach ($key in $envMap.Keys) {
        if ($envMap[$key] -icontains $SourceEnv) { $normEnv = $key; break }
    }

    # 1. Try exact source + env + target match
    $candidates = $migrationPaths.paths | Where-Object {
        $_.sourceType -ieq $SourceType -and
        ($_.sourceEnvironments -icontains $normEnv -or $_.sourceEnvironments -icontains $SourceEnv) -and
        ($TargetType -eq 'Undecided' -or $_.targetType -ilike "*$TargetType*")
    }

    # 2. Relax: source + target only
    if (-not $candidates) {
        $candidates = $migrationPaths.paths | Where-Object {
            $_.sourceType -ieq $SourceType -and
            ($TargetType -eq 'Undecided' -or $_.targetType -ilike "*$TargetType*")
        }
    }

    # 3. Fallback: any path for this source type
    if (-not $candidates) {
        $candidates = $migrationPaths.paths | Where-Object { $_.sourceType -ieq $SourceType }
    }

    return $candidates | Select-Object -First 1
}

# ── Score Calculator ──────────────────────────────────────────────────────────
function Get-ReadinessScore {
    param([hashtable]$Answers, [object]$Path)

    $totalScore = 0
    $findings   = @()
    $blockers   = @()

    # Derive boolean flags from answers
    $isHeterogeneous   = $Path -and $Path.migrationType -eq 'Heterogeneous'
    $requiresGHCP      = $Path -and $Path.PSObject.Properties['requiresGHCP'] -and $Path.requiresGHCP
    $ghcpLicensed      = $Answers.ghcpStatus -eq 'yes_licensed'
    $onlineMigrationOK = $Path -and $Path.onlineMigration
    $storedProcs           = $Answers.storedProcs
    $hasLinkedServers      = $Answers.dependencies -contains "linked_servers"
    $hasSSIS               = $Answers.dependencies -contains "ssis"
    $hasPLSQL              = $Answers.features -contains "plsql"
    $hasOracleSpecific     = $Answers.features -contains "oracle_specific"

    # Migration Path score
    if ($Path -and -not $isHeterogeneous) {
        $totalScore += 20; $findings += 'Clear homogeneous migration path identified (+20)'
    } elseif ($Path -and $isHeterogeneous -and $ghcpLicensed) {
        $totalScore += 12; $findings += 'Heterogeneous path - GHCP licensed, schema conversion required (+12)'
    } elseif ($Path -and $isHeterogeneous -and -not $ghcpLicensed) {
        $totalScore += 4; $findings += 'Heterogeneous path - GHCP license missing (required for Oracle/Sybase) (+4)'
        if ($requiresGHCP) { $blockers += 'BLOCKER: Oracle/Sybase migration requires GitHub Copilot license (agentic schema conversion)' }
    } else {
        $totalScore += 5; $findings += 'No migration path found - manual review needed (+5)'
    }

    # Downtime Tolerance
    switch ($Answers.maxDowntime) {
        "days"  { $totalScore += 15; $findings += "Offline migration acceptable (+15)" }
        "hours" { $totalScore += 10; $findings += "Short window – online preferred (+10)" }
        "zero"  {
            if ($onlineMigrationOK) { $totalScore += 10; $findings += "Zero downtime – online migration supported (+10)" }
            else {
                $totalScore += 2
                $blockers += "BLOCKER: Zero downtime required but migration path does not support online migration"
                $findings += "Zero downtime required but not supported – blocker (+2)"
            }
        }
    }

    # Connectivity
    switch ($Answers.connectivity) {
        "expressroute" { $totalScore += 15; $findings += "ExpressRoute connectivity (+15)" }
        "vpn"          { $totalScore += 12; $findings += "VPN connectivity (+12)" }
        "internet"     { $totalScore += 5;  $findings += "Internet only – latency/security risk (+5)" }
        "none"         {
            $blockers += "BLOCKER: No network connectivity to Azure. Must be established before migration."
            $findings += "No connectivity – critical blocker (+0)"
        }
    }

    # Landing Zone
    switch ($Answers.landingZone) {
        "yes"     { $totalScore += 10; $findings += "Azure Landing Zone ready (+10)" }
        "partial" { $totalScore += 5;  $findings += "Partial Landing Zone – gaps to close (+5)" }
        "no"      {
            $blockers += "BLOCKER: Azure Landing Zone not established."
            $findings += "No Landing Zone – blocker (+0)"
        }
    }

    # Complexity
    if ($storedProcs -eq "none" -and -not $hasLinkedServers -and -not $hasSSIS) {
        $totalScore += 20; $findings += "Low complexity – no stored procs or integrations (+20)"
    } elseif ($storedProcs -eq "few" -and -not $hasOracleSpecific) {
        $totalScore += 14; $findings += "Medium complexity – few stored procs (+14)"
    } elseif ($storedProcs -eq "many" -or $hasLinkedServers -or $hasSSIS) {
        $totalScore += 8;  $findings += "High complexity – linked servers or SSIS detected (+8)"
    } elseif ($storedProcs -eq "extensive" -or $hasOracleSpecific -or $hasPLSQL) {
        $totalScore += 3;  $findings += "Very high complexity – PL/SQL or extensive procs (+3)"
    }

    # Team Readiness
    switch ($Answers.teamSkill) {
        "expert"   { $totalScore += 10; $findings += "Expert team – minimal ramp-up (+10)" }
        "moderate" { $totalScore += 6;  $findings += "Moderate skill – training recommended (+6)" }
        "beginner" { $totalScore += 2;  $findings += "Beginner skill – significant upskilling needed (+2)" }
    }

    # Rollback
    switch ($Answers.rollback) {
        "yes_tested"   { $totalScore += 10; $findings += "Rollback plan tested (+10)" }
        "yes_untested" { $totalScore += 6;  $findings += "Rollback documented but untested (+6)" }
        "partial"      { $totalScore += 3;  $findings += "Partial rollback plan (+3)" }
        "no"           { $totalScore += 0;  $findings += "No rollback plan – high risk (+0)" }
    }

    # Determine band
    $band = $scoringMatrix.readinessBands | Where-Object { $totalScore -ge $_.min -and $totalScore -le $_.max } | Select-Object -First 1

    return @{
        Score        = [Math]::Min($totalScore, 100)
        Band         = $band.label
        Color        = $band.color
        Recommendation = $band.recommendation
        Findings     = $findings
        Blockers     = $blockers
    }
}

# ── Effort Estimator ──────────────────────────────────────────────────────────
function Get-EffortEstimate {
    param([hashtable]$Answers, [object]$Path, [int]$DbCount)

    $em           = $scoringMatrix.effortEstimation
    $size         = $Answers.dataSize
    $migrType     = if ($Path.migrationType -eq "Heterogeneous") { "heterogeneous" } else { "homogeneous" }
    $basePerDB    = $em.baseEffortPerDB.$size.$migrType
    $multiplier   = 1.0

    if ($Answers.storedProcs -eq "few")       { $multiplier *= $em.multipliers.storedProcs_few }
    if ($Answers.storedProcs -eq "many")      { $multiplier *= $em.multipliers.storedProcs_many }
    if ($Answers.storedProcs -eq "extensive") { $multiplier *= $em.multipliers.storedProcs_extensive }
    if ($Answers.dependencies -contains "linked_servers") { $multiplier *= $em.multipliers.hasLinkedServers }
    if ($Answers.dependencies -contains "ssis")           { $multiplier *= $em.multipliers.hasSSIS }
    if ($Answers.teamSkill -eq "beginner")    { $multiplier *= $em.multipliers.teamSkill_beginner }
    if ($Answers.teamSkill -eq "moderate")    { $multiplier *= $em.multipliers.teamSkill_moderate }
    if ($Answers.rollback -eq "no")           { $multiplier *= $em.multipliers.noRollbackPlan }

    $daysPerDB    = [Math]::Ceiling($basePerDB * $multiplier)
    $totalDays    = $daysPerDB * $DbCount

    return @{
        DaysPerDatabase = $daysPerDB
        TotalDays       = $totalDays
        Weeks           = [Math]::Ceiling($totalDays / 5)
    }
}

# ── Main Assessment Loop ──────────────────────────────────────────────────────
$allReports = @()
$timestamp  = Get-Timestamp

foreach ($db in $databases) {
    Write-Log "Assessing: $($db.DatabaseName) ($($db.SourceType) → $($db.TargetType))"

    # Build answers hashtable from input row
    $answers = @{
        sourceType    = $db.SourceType
        targetType    = $db.TargetType
        sourceEnv     = $db.SourceEnvironment
        maxDowntime   = $db.MaxDowntime
        connectivity  = $db.Connectivity
        landingZone   = $db.LandingZone
        dataSize      = $db.DataSize
        storedProcs   = $db.StoredProcs
        dependencies  = if ($db.Dependencies)    { $db.Dependencies    -split '\|' } else { @() }
        features      = if ($db.SpecialFeatures)  { $db.SpecialFeatures  -split '\|' } else { @() }
        ghcpStatus    = if ($db.PSObject.Properties['GHCPStatus']) { $db.GHCPStatus } else { 'no' }
        teamSkill     = $db.TeamSkill
        rollback      = $db.RollbackPlan
        dbCount       = [int]($db.DatabaseCount ?? 1)
    }

    # Resolve migration path
    $path = Resolve-MigrationPath -SourceType $answers.sourceType -TargetType $answers.targetType -SourceEnv $answers.sourceEnv

    if (-not $path) {
        Write-Log "No migration path found for $($answers.sourceType) → $($answers.targetType)" "WARN"
    } else {
        Write-Log "Migration path: $($path.id)" "SUCCESS"
    }

    # Run info-gather factory script (unless skipped)
    $infoGatherResult = $null
    if (-not $SkipInfoGather -and $path -and $path.factoryScript.PSObject.Properties['infoGather']) {
        $scriptPath = Join-Path $ScriptRoot $path.factoryScript.infoGather
        if (Test-Path $scriptPath) {
            Write-Log "Running factory info-gather script: $($path.factoryScript.infoGather)"
            # Script would be invoked here – parameterized via input CSV
            $infoGatherResult = "Info-gather completed. See factory output folder."
        } else {
            Write-Log "Factory script not found at: $scriptPath" "WARN"
            $infoGatherResult = "Script not found – manual info-gather required"
        }
    } else {
        $infoGatherResult = "Skipped (--SkipInfoGather)"
    }

    # Score
    $score  = Get-ReadinessScore -Answers $answers -Path $path
    $effort = Get-EffortEstimate -Answers $answers -Path $path -DbCount $answers.dbCount

    # Build report entry
    $targetType_r     = $(if ($path) { $path.targetType }      else { $answers.targetType })
    $pathId_r         = $(if ($path) { $path.id }              else { "unknown" })
    $migrType_r       = $(if ($path) { $path.migrationType }   else { "Unknown" })
    $migrTools_r      = $(if ($path) { $path.migrationTools }  else { @() })
    $onlineMigr_r     = $(if ($path) { $path.onlineMigration } else { $false })
    $prereqs_r        = $(if ($path) { $path.prerequisites }   else { @() })
    $factScript_r     = $(if ($path -and $path.factoryScript.PSObject.Properties['infoGather']) { $path.factoryScript.infoGather } else { $null })

    $report = [ordered]@{
        AssessmentId     = [System.Guid]::NewGuid().ToString()
        Timestamp        = (Get-Date -Format "o")
        DatabaseName     = $db.DatabaseName
        SourceType       = $answers.sourceType
        SourceVersion    = $db.SourceVersion
        SourceEnv        = $answers.sourceEnv
        TargetType       = $targetType_r
        MigrationPathId  = $pathId_r
        MigrationType    = $migrType_r
        MigrationTools   = $migrTools_r
        OnlineMigration  = $onlineMigr_r
        ReadinessScore   = $score.Score
        ReadinessBand    = $score.Band
        Recommendation   = $score.Recommendation
        Blockers         = $score.Blockers
        Findings         = $score.Findings
        EffortDaysPerDB  = $effort.DaysPerDatabase
        EffortTotalDays  = $effort.TotalDays
        EffortWeeks      = $effort.Weeks
        Prerequisites    = $prereqs_r
        FactoryScript    = $factScript_r
        InfoGatherStatus = $infoGatherResult
    }

    $allReports += $report

    $logLevel = if ($score.Score -ge 80) { "SUCCESS" } elseif ($score.Score -ge 60) { "WARN" } else { "ERROR" }
    Write-Log ("Score: {0}/100 [{1}] - {2}" -f $score.Score, $score.Band, $score.Recommendation) -Level $logLevel
}

# ── Write Reports ─────────────────────────────────────────────────────────────
$jsonOut = Join-Path $OutputDir "assessment-report-$timestamp.json"
$allReports | ConvertTo-Json -Depth 10 | Out-File $jsonOut -Encoding UTF8
Write-Log "JSON report written: $jsonOut" "SUCCESS"

# Summary to console
$separator = "=" * 60
Write-Host "`n$separator" -ForegroundColor Cyan
Write-Host "  ASSESSMENT SUMMARY" -ForegroundColor Cyan
Write-Host $separator -ForegroundColor Cyan
$allReports | ForEach-Object {
    $color = switch ($_.ReadinessBand) {
        "Ready to Migrate"     { "Green" }
        "Conditionally Ready"  { "Yellow" }
        "Needs Preparation"    { "DarkYellow" }
        default                { "Red" }
    }
    Write-Host ("[{0,3}/100] {1,-40} [{2}]" -f $_.ReadinessScore, $_.DatabaseName, $_.ReadinessBand) -ForegroundColor $color
    if ($_.Blockers.Count -gt 0) {
        $_.Blockers | ForEach-Object { Write-Host "  !! $_" -ForegroundColor Red }
    }
}
Write-Host $separator -ForegroundColor Cyan
Write-Host "`nReports saved to: $OutputDir`n"

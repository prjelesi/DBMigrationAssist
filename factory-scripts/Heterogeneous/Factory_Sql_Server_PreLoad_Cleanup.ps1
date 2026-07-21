#---------------------------------------------------------------------------------------------------------------------------*
#  Purpose        : Script to migrate larger numbers of databases using Migration service.
#  Schedule       : Ad-Hoc / On-Demand
#  Date           : 02-December-2025
#  Author         : Akli IMARAZENE
#  Version        : 1.1
#   
#  VARIABLE       : NONE
#  PARENT         : NONE
#  CHILD          : NONE
#---------------------------------------------------------------------------------------------------------------------------*
#---------------------------------------------------------------------------------------------------------------------------*
#
#
#---------------------------------------------------------------------------------------------------------------------------*
#---------------------------------------------------------------------------------------------------------------------------*
# Usage:
# Powershell.exe -File .\CMF-MSSQL-MigrateUsingMigrationService.ps1
#
#




  function exitCode{
    Write-Host "-Ending Execution"
    exit
}

function createFolder([string]$newFolder) {
    if(Test-Path $newFolder)
    {
        Write-Host "-Folder'$newFolder' Exist..."
    }
    else
    {
        New-Item $newFolder -ItemType Directory
        Write-Host "-$newFolder folder created..."
    }
}

$Folder = $PSScriptRoot
#$Folder="C:\Users\v-madagrawal\csu-MSSQL-mf\PUBLIC"
$mssqlpath = where.exe sqlcmd
$Triggerpsql_File_Path=$Folder+"\Trigger_psql.bat"
$date = Get-Date -Format "yy-dd-MM-hh-mm"
#$Log_Name= $Host_Name.replace(".", "_")
$DbGather_Path=$Folder+"\MSSQL_Templates\pg_db_gather_db.sql"
$DbGather_Server_Path=$Folder+"\MSSQL_Templates\pg_db_gather_server.sql"
$DetailedInfo_Path=$Folder+"\MSSQL_Templates\pg_db_maintenance.sql"
$DbList_path=$Folder+"\MSSQL_Templates\DB_List.sql"



#---------------------------------------------------------PROGRAM BEGINS HERE----------------------------------------------------------


Clear-Host
Write-Host " "
Write-Host "                                                                               " -ForegroundColor White -BackgroundColor Magenta
Write-Host "           Welcome to Factory - MSSQL_info_Gathering_Automation                " -ForegroundColor White -BackgroundColor Magenta
Write-Host "           (OSS DB Migration Factory)                                          " -ForegroundColor White -BackgroundColor Magenta

Write-Host "                                                                               " -ForegroundColor White -BackgroundColor Magenta
Write-Host " "
Write-Host " "

Write-Host "==============================================================================="
Write-Host " "
Write-Host "Script executed : $PSCommandPath"
Write-Host " "
Write-Host "==============================================================================="
Write-Host " "



Write-Host "=== Environment Verification ===" -ForegroundColor Cyan

# Summary array
$VerificationSummary = @()

# ---------------------------------------------------
# 1. Verify PowerShell & Invoke-Sqlcmd installation
# ---------------------------------------------------
Write-Host "`n[PowerShell & SQL Cmdlet Verification]" -ForegroundColor Magenta

# ---- PowerShell verification ----
if ($PSVersionTable -and $PSVersionTable.PSVersion) {

    $pwshVersion = $PSVersionTable.PSVersion
    $pwshPath = (Get-Process -Id $PID).Path

    Write-Host "PowerShell is installed" -ForegroundColor Green
    Write-Host "PowerShell Version : $pwshVersion"
    Write-Host "PowerShell Path    : $pwshPath"

    $VerificationSummary += [PSCustomObject]@{
        "Validation Type" = "PowerShell"
        "Status"          = "SUCCESS"
        "Comments"        = "Version $pwshVersion - Path: $pwshPath"
    }

} else {

    Write-Host "PowerShell is NOT installed or not accessible" -ForegroundColor Red

    $VerificationSummary += [PSCustomObject]@{
        "Validation Type" = "PowerShell"
        "Status"          = "ERROR"
        "Comments"        = "PowerShell not found"
    }
}

 
# ---- Invoke-Sqlcmd verification ----
# ---- Invoke-Sqlcmd verification ----
if (Get-Command Invoke-Sqlcmd -ErrorAction SilentlyContinue) {

    $sqlCmd = Get-Command Invoke-Sqlcmd
    $sqlModule = $sqlCmd.Source

    Write-Host "Invoke-Sqlcmd is installed" -ForegroundColor Green
    Write-Host "Module Source : $sqlModule"

    $VerificationSummary += [PSCustomObject]@{
        "Validation Type" = "Invoke-Sqlcmd"
        "Status"          = "SUCCESS"
        "Comments"        = "Available via module: $sqlModule"
    }

} else {

    Write-Host "`nERROR: Invoke-Sqlcmd is not installed." -ForegroundColor Red
    Write-Host "This script requires the SqlServer PowerShell module to continue." -ForegroundColor Red

    Write-Host "`nHow to install:" -ForegroundColor Yellow
    Write-Host "1. Open PowerShell as Administrator" -ForegroundColor Yellow
    Write-Host "2. Run the following command:" -ForegroundColor Yellow
    Write-Host "   Install-Module -Name SqlServer -Repository PSGallery -Force" -ForegroundColor Cyan
    Write-Host "3. Restart PowerShell and re-run the script" -ForegroundColor Yellow

    $VerificationSummary += [PSCustomObject]@{
        "Validation Type" = "Invoke-Sqlcmd"
        "Status"          = "ERROR"
        "Comments"        = "SqlServer module not found"
    }

    Exit 1
}
# ---------------------------------------------------
# 2. Check if SQL Server Client / sqlcmd installed
# ---------------------------------------------------
Write-Host "`n[SQL Server Client Verification]" -ForegroundColor Magenta

$sqlcmdPath = (Get-Command sqlcmd.exe -ErrorAction SilentlyContinue).Source

if ($sqlcmdPath) {
    # Try to extract sqlcmd version
    try {
        $sqlcmdVersion = (sqlcmd -? | Select-String "Version").ToString().Trim()
    } catch { 
        $sqlcmdVersion = "Unknown"
    }

    Write-Host "SQL Client Installed : YES" -ForegroundColor Green
    Write-Host "sqlcmd Path          : $sqlcmdPath"
    Write-Host "sqlcmd Version       : $sqlcmdVersion"

    $VerificationSummary += [PSCustomObject]@{
        "Validation Type" = "SQL Client (sqlcmd)"
        "Status"          = "SUCCESS"
        "Comments"        = "Version: $sqlcmdVersion - Path: $sqlcmdPath"
    }
}
else {
    Write-Host "SQL Client Installed : NO" -ForegroundColor Red

    $VerificationSummary += [PSCustomObject]@{
        "Validation Type" = "SQL Client (sqlcmd)"
        "Status"          = "FAILED"
        "Comments"        = "sqlcmd.exe not found"
    }
}

# ---------------------------------------------------
# 3. Check SQL Server Management Objects (SMO)
# ---------------------------------------------------
Write-Host "`n[SQL Server Management Objects (SMO)]" -ForegroundColor Magenta

try {
    # Try loading SMO library
    Add-Type -AssemblyName "Microsoft.SqlServer.Smo" -ErrorAction Stop

    $smoAssembly = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo")
    $smoVersion = $smoAssembly.GetName().Version
    $smoPath = $smoAssembly.Location

    Write-Host "SMO Installed : YES" -ForegroundColor Green
    Write-Host "SMO Version   : $smoVersion"
    Write-Host "SMO Path      : $smoPath"

    $VerificationSummary += [PSCustomObject]@{
        "Validation Type" = "SQL Server Management Objects"
        "Status"          = "SUCCESS"
        "Comments"        = "Version: $smoVersion - Path: $smoPath"
    }
}
catch {
    Write-Host "SMO Installed : NO" -ForegroundColor Red
    Write-Host "SMO not found on system."

    $VerificationSummary += [PSCustomObject]@{
        "Validation Type" = "SQL Server Management Objects"
        "Status"          = "FAILED"
        "Comments"        = "SMO assemblies not found"
    }
}

# ---------------------------------------------------
# Final Summary Table
# ---------------------------------------------------
Write-Host "`n=== Verification Summary ===" -ForegroundColor Cyan

$VerificationSummary | Format-Table -AutoSize






Write-Host " "
Write-Host "==============================================================================="
Write-Host " "




Write-Host " "





$validChoices = @("1","2","0")
do {
    $choiceInput = Read-Host "MSSQL authentication type (1=SQL, 2=AD/Windows, 0=Exit) [default 2]"
    $choice = if ([string]::IsNullOrWhiteSpace($choiceInput)) { "2" } else { $choiceInput }

    if ($choice -eq "0") {
        Write-Host "Exit selected. Bye!"
        exit
    }

    if ($validChoices -notcontains $choice) {
        Write-Host "Invalid choice! Please select 1, 2, or 0" -ForegroundColor Red
    }
} until ($validChoices -contains $choice)

# -------------------------------
# Step 2: Hostname and Instance
# -------------------------------
do {
    $hostnameInput = Read-Host "Enter server hostname [default: localhost]"
    $hostname = if ([string]::IsNullOrWhiteSpace($hostnameInput)) { "localhost" } else { $hostnameInput }

    $instanceInput = Read-Host "Enter instance name [default: MSSQLSERVER]"
    $instance = if ([string]::IsNullOrWhiteSpace($instanceInput)) { "MSSQLSERVER" } else { $instanceInput }

	$portInput = Read-Host "Enter SQL port [default: 1433]"
	$port = if ([string]::IsNullOrWhiteSpace($portInput)) {
    	1433
	} elseif ($portInput -match '^\d+$') {
    	[int]$portInput
	} else {
    	Write-Host "Invalid port. Using default 1433." -ForegroundColor Yellow
    	1433
}

    if ($instance.ToUpper() -eq "MSSQLSERVER") {
         $serverInstance = "$hostname,$port"
    } else {
       $serverInstance = "$hostname\$instance,$port"
    }


 

    # -------------------------------
    # Step 3: Credentials and Connection Test
    # -------------------------------
 if ($choice -eq "1") {
        do {
            $username = Read-Host "Enter SQL username"
            if ([string]::IsNullOrWhiteSpace($username)) {
                Write-Host "Username is mandatory!" -ForegroundColor Red
            }
        } until (-not [string]::IsNullOrWhiteSpace($username))

        do {
           $passwordSecure = Read-Host -Prompt "Enter password for $username" -AsSecureString
            if (-not $passwordSecure) { Write-Host "passwordSecure is mandatory!" -ForegroundColor Red }
        } until ($passwordSecure)

 		$plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
			[Runtime.InteropServices.Marshal]::SecureStringToBSTR($passwordSecure)
		)
		$connString = "Server=$serverInstance;User ID=$username;Password=$plainPassword;Encrypt=False;TrustServerCertificate=True;"
 
        try {
 			Invoke-Sqlcmd -ConnectionString $connString -Query "SELECT 1;"	-ErrorAction Stop | Out-Null
            $connectionOK = $true
            Write-Host "Successfully connected to SQL Server instance '$serverInstance' using SQL credentials." -ForegroundColor Green
        } catch {

            Write-Host "ERROR: Cannot connect to SQL Server instance '$serverInstance' with provided SQL credentials." -ForegroundColor Red
 		Write-Host "Invoke-Sqlcmd -ConnectionString $connString -Query  SELECT 1;"
				Invoke-Sqlcmd -ConnectionString $connString -Query "SELECT 1;"
            $connectionOK = $false
        }

    } else {
        $cred = $null
        Write-Host "`nTrying to connect to SQL Server '$serverInstance' using current Windows credentials..." -ForegroundColor Green
        try {
            Invoke-Sqlcmd -ServerInstance $serverInstance -Database master -Query "SELECT 1" -ErrorAction Stop | Out-Null
            $connectionOK = $true
            Write-Host "Successfully connected to SQL Server instance '$serverInstance' using current Windows credentials." -ForegroundColor Green
        } catch {
            Write-Host "ERROR: Cannot connect to SQL Server instance '$serverInstance' using current Windows credentials." -ForegroundColor Red
		Write-Host "Invoke-Sqlcmd -ConnectionString $connString -Query  SELECT 1;"
            $connectionOK = $false
        }
    }

} until ($connectionOK)

# -------------------------------
# Step 4: Database Selection (default * for all)
# -------------------------------
try {
    Write-Host "`nRetrieving list of databases from '$serverInstance'..." -ForegroundColor Green

    if ($choice -eq "1") {
		$db= "master" 
		$connString = "Server=$serverInstance;Database=$database;User ID=$username;Password=$plainPassword;Encrypt=False;TrustServerCertificate=True;"

        $allDatabases =  Invoke-Sqlcmd -ConnectionString $connString   -Query   "SELECT name FROM sys.databases WHERE name NOT IN ('master','tempdb','model','msdb');" | Select-Object -ExpandProperty name
    } else {
        $allDatabases = Invoke-Sqlcmd -ServerInstance $serverInstance -Database master -Query "SELECT name FROM sys.databases WHERE name NOT IN ('master','tempdb','model','msdb');" | Select-Object -ExpandProperty name
    }

    Write-Host "`nAvailable databases:"
    $allDatabases | ForEach-Object { Write-Host " - $_" }

} catch {
    Write-Host "ERROR: Failed to retrieve databases from $serverInstance." -ForegroundColor Red
    exit
}

do {
    $databaseListRaw = Read-Host "`nEnter list of databases (comma/space separated) or * for all [default *]"
    $databaseListRaw = if ([string]::IsNullOrWhiteSpace($databaseListRaw)) { "*" } else { $databaseListRaw.Trim() }

    if ($databaseListRaw -eq "*") {
        $databases = $allDatabases
        $validSelection = $true
    } else {
        $databases = $databaseListRaw -split "[ ,]+" | ForEach-Object { $_.Trim() }
        $invalidDBs = $databases | Where-Object { $allDatabases -notcontains $_ }

        if ($invalidDBs) {
            Write-Host "`nERROR: The following databases do not exist on the server: $($invalidDBs -join ', ')" -ForegroundColor Red
            Write-Host "Please select from the available databases only."
            $validSelection = $false
        } else {
            $validSelection = $true
        }
    }

} until ($validSelection)

Write-Host "`nSelected databases: $($databases -join ', ')" -ForegroundColor Green

# -------------------------------
# Step 0: Prompt for working directory (loop until valid or 0 to exit)
# -------------------------------
do {
    Write-Host "`nEnter the working directory where the scripts will be generated."
    Write-Host "Type '0' to exit."
    $workingDirInput = Read-Host "Working directory"

    if ($workingDirInput -eq "0") {
        Write-Host "Exit selected. Bye!"
        exit
    }

    if ([string]::IsNullOrWhiteSpace($workingDirInput)) {
        Write-Host "Working directory is mandatory!" -ForegroundColor Red
        $validDir = $false
        continue
    }

    if (-not (Test-Path $workingDirInput)) {
        Write-Host "ERROR: Directory '$workingDirInput' does not exist." -ForegroundColor Red
        $validDir = $false
    } else {
        $workingDir = $workingDirInput
        $validDir = $true
    }
} until ($validDir)

Write-Host "===================================================================="
Write-Host " "
Write-Host "Scripts will be generated in: $workingDir" -ForegroundColor Green


Write-Host "Please select the assessment operation to perform" -ForegroundColor Green
Write-Host "===================================================================="
Write-Host "GenerateSQL Cleanup:"
Write-Host "			  11. Drop FK"
Write-Host " 			  12. Disable Triggers"
Write-Host " 			  13. Cleanup Tables"
Write-Host " Run Pre-Migration:"
Write-Host " 			  21. Drop FK"
Write-Host " 			  22. Disable Triggers"
Write-Host " 			  23. Cleanup Tables"
Write-Host "Run Post-Migration:"
Write-Host "			  31. Enable FK"
Write-Host " 			  32. Enable Triggers"
Write-Host "4. Validate Pre-Migration & Post-Migration Log Files"
Write-Host "5. Databases inventory (FK/ TRIGGERS/TABLES)"
Write-Host "6. Execute Sql Script"

Write-Host " "
Write-Host "0. Exit"
 Write-Host " "

 $validInputs = @("11","12","13","21","22","23","31","32","4","5","0","6")

do {
    $raw = Read-Host "Please enter choice(s) (e.g., 11 12 13,...) or 0 to Exit"

    # Remove non-printable characters, trim spaces
    $raw = ($raw -replace '[^\S ]','').Trim()

    # Split input on spaces or commas
    $inputs = $raw -split "[ ,]+" | ForEach-Object { $_.Trim() }

    # Exit if exactly 0
    if ($inputs.Count -eq 1 -and $inputs[0] -eq "0") {
        Write-Host "Exit selected. Bye!" -ForegroundColor Yellow
        exit
    }

    # Validate inputs against allowed choices
    $invalid = $inputs | Where-Object { $_ -notin $validInputs }

    if ($invalid.Count -gt 0) {
        Write-Host "Invalid input! Please choose only from: $($validInputs -join ', ')" -ForegroundColor Red
    }

} until ($invalid.Count -eq 0)

Write-Host "Valid selection(s): $($inputs -join ', ')" -ForegroundColor Green



## Block 11: Recreated Foreign Key Cleanup and Script Generator

   
# --- Corrected Block 11: Valid FK Script Generator (fixed column ordering) ---

 if ($inputs -contains "11") {

    Write-Host "GenerateSQL Cleanup for Foreign Keys ..." -ForegroundColor Green

    # Ensure FK directory exists
    $fkDir = Join-Path $workingDir "FK"
    if (-not (Test-Path $fkDir)) { New-Item -Path $fkDir -ItemType Directory | Out-Null }

    # Ensure LOG directory exists
    $logDir = Join-Path $fkDir "LOG"
    if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory | Out-Null }

    foreach ($db in $databases) {

        Write-Host "`nGenerating FK scripts for database '$db'..." -ForegroundColor Green

        # Query for FK information
        $query = @"
SELECT 
    fk.object_id AS FK_ID,
    fk.name AS FK_Name,
    SCHEMA_NAME(tp.schema_id) AS ParentSchema,
    tp.name AS ParentTable,
    cp.name AS ParentColumn,
    SCHEMA_NAME(tr.schema_id) AS RefSchema,
    tr.name AS RefTable,
    cr.name AS RefColumn,
    fk.delete_referential_action_desc,
    fk.update_referential_action_desc,
    fkc.constraint_column_id
FROM sys.foreign_keys fk
JOIN sys.foreign_key_columns fkc 
    ON fk.object_id = fkc.constraint_object_id
JOIN sys.tables tp 
    ON fkc.parent_object_id = tp.object_id
JOIN sys.columns cp 
    ON fkc.parent_object_id = cp.object_id 
    AND fkc.parent_column_id = cp.column_id
JOIN sys.tables tr 
    ON fkc.referenced_object_id = tr.object_id
JOIN sys.columns cr 
    ON fkc.referenced_object_id = cr.object_id 
    AND fkc.referenced_column_id = cr.column_id
WHERE tp.is_ms_shipped = 0
  AND tr.is_ms_shipped = 0
ORDER BY fk.object_id, fkc.constraint_column_id;
"@

        try {
            if ($choice -eq "1") {
                $connString = "Server=$serverInstance;Database=$db;User ID=$username;Password=$plainPassword;Encrypt=False;TrustServerCertificate=True;"
                $fkData = Invoke-Sqlcmd -ConnectionString $connString -Query $query
            } else {
                $fkData = Invoke-Sqlcmd -ServerInstance $serverInstance -Database $db -Query $query
            }
        } catch {
            Write-Host "ERROR: Cannot fetch FK info from database '$db'. Skipping..." -ForegroundColor Red
            continue
        }

        # Prepare output files
        $dropFile   = Join-Path $fkDir "DropFKs_${db}.sql"
        $createFile = Join-Path $fkDir "CreateFKs_${db}.sql"
        $dropLog    = Join-Path $logDir "DropFKs_${db}.log"
        $createLog  = Join-Path $logDir "CreateFKs_${db}.log"

        if (-not $fkData -or $fkData.Count -eq 0) {
            Write-Host "No user-defined foreign keys found in database '$db'. Generating empty SQL files..." -ForegroundColor Yellow

            # Generate empty SQL files to replace existing ones
            "USE [$db];`r`nGO`r`n-- No foreign keys found" | Out-File -FilePath $dropFile -Encoding UTF8
            "USE [$db];`r`nGO`r`n-- No foreign keys found" | Out-File -FilePath $createFile -Encoding UTF8

            # Generate empty logs
            @(
                "Drop FK script generated on $(Get-Date)",
                "No foreign keys found."
            ) | Out-File -FilePath $dropLog -Encoding UTF8

            @(
                "Create FK script generated on $(Get-Date)",
                "No foreign keys found."
            ) | Out-File -FilePath $createLog -Encoding UTF8

            Write-Host "Empty Drop/Create FK SQL and logs generated for database '$db'." -ForegroundColor Cyan
            continue
        }

        # Group properly by FK_ID
        $fkGroups = $fkData | Group-Object FK_ID
        $processedFKs = @()
        $dropScript = ""
        $createScript = ""

        foreach ($grp in $fkGroups) {
            $rows = $grp.Group
            $fkName = $rows[0].FK_Name
            $parentSchema = $rows[0].ParentSchema
            $parentTable = $rows[0].ParentTable
            $refSchema = $rows[0].RefSchema
            $refTable = $rows[0].RefTable
            $processedFKs += $fkName

            # DROP script
            $dropScript += @"
IF OBJECT_ID('$fkName','F') IS NOT NULL
BEGIN
    ALTER TABLE [$parentSchema].[$parentTable] DROP CONSTRAINT [$fkName];
END
GO

"@

            # Columns in correct order
            $parentColumns = ($rows | Sort-Object constraint_column_id | ForEach-Object { $_.ParentColumn }) -join ", "
            $refColumns    = ($rows | Sort-Object constraint_column_id | ForEach-Object { $_.RefColumn }) -join ", "

            $onDeleteClause = if ($rows[0].delete_referential_action_desc -ne "NO_ACTION") { " ON DELETE $($rows[0].delete_referential_action_desc)" } else { "" }
            $onUpdateClause = if ($rows[0].update_referential_action_desc -ne "NO_ACTION") { " ON UPDATE $($rows[0].update_referential_action_desc)" } else { "" }

            # CREATE script
            $createScript += @"
ALTER TABLE [$parentSchema].[$parentTable]
ADD CONSTRAINT [$fkName] FOREIGN KEY ($parentColumns)
REFERENCES [$refSchema].[$refTable] ($refColumns)$onDeleteClause$onUpdateClause;
GO

"@
        }

        # Write DROP script and log
        $dropHeader = @"
USE [$db];
GO

-- Drop FK script for database '$db'
-- Number of foreign keys: $($processedFKs.Count)

"@
        ($dropHeader + $dropScript) | Out-File -FilePath $dropFile -Encoding UTF8

        @(
            "Drop FK script generated on $(Get-Date)",
            "Number of foreign keys processed: $($processedFKs.Count)",
            "Foreign keys list:",
            $processedFKs
        ) | Out-File -FilePath $dropLog -Encoding UTF8

        # Write CREATE script and log
        $createHeader = @"
USE [$db];
GO

-- Create FK script for database '$db'
-- Number of foreign keys: $($processedFKs.Count)

"@
        ($createHeader + $createScript) | Out-File -FilePath $createFile -Encoding UTF8

        @(
            "Create FK script generated on $(Get-Date)",
            "Number of foreign keys processed: $($processedFKs.Count)",
            "Foreign keys list:",
            $processedFKs
        ) | Out-File -FilePath $createLog -Encoding UTF8

        Write-Host "Drop/Create FK scripts and logs generated for database '$db'." -ForegroundColor Cyan
    }

    Write-Host "`nAll FK scripts and logs generated in folder: $fkDir" -ForegroundColor Green
}


if ($inputs -contains "12") {

    Write-Host "GenerateSQL Cleanup for Triggers ..." -ForegroundColor Green

    # Ensure TRIGGER directory exists
    $triggerDir = Join-Path $workingDir "TRIGGERS"
    if (-not (Test-Path $triggerDir)) { New-Item -Path $triggerDir -ItemType Directory | Out-Null }

    # Ensure LOG directory exists
    $logDir = Join-Path $triggerDir "LOG"
    if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory | Out-Null }

    foreach ($db in $databases) {

        Write-Host "`nGenerating Trigger scripts for database '$db'..." -ForegroundColor Green

        $query = @"
SELECT 
    s.name AS SchemaName,
    t.name AS TableName,
    tr.name AS TriggerName
FROM sys.triggers tr
JOIN sys.tables t ON tr.parent_id = t.object_id
JOIN sys.schemas s ON t.schema_id = s.schema_id
WHERE tr.is_ms_shipped = 0
ORDER BY s.name, t.name, tr.name;
"@

        try {
            if ($choice -eq "1") {
                $connString = "Server=$serverInstance;Database=$db;User ID=$username;Password=$plainPassword;Encrypt=False;TrustServerCertificate=True;"
                $trigData = Invoke-Sqlcmd -ConnectionString $connString -Query $query
            } else {
                $trigData = Invoke-Sqlcmd -ServerInstance $serverInstance -Database $db -Query $query
            }
        } catch {
            Write-Host "ERROR: Cannot fetch trigger info from '$db'. Skipping..." -ForegroundColor Red
            continue
        }

        $disableFile = Join-Path $triggerDir "DisableTriggers_${db}.sql"
        $enableFile  = Join-Path $triggerDir "EnableTriggers_${db}.sql"
        $disableLog  = Join-Path $logDir "DisableTriggers_${db}.log"
        $enableLog   = Join-Path $logDir "EnableTriggers_${db}.log"

        if (-not $trigData -or $trigData.Count -eq 0) {
            Write-Host "No triggers found in database '$db'. Generating empty SQL files..." -ForegroundColor Yellow

            "USE [$db];`r`nGO`r`n-- No triggers found" | Out-File -FilePath $disableFile -Encoding UTF8
            "USE [$db];`r`nGO`r`n-- No triggers found" | Out-File -FilePath $enableFile -Encoding UTF8

            @(
                "Disable Trigger script generated on $(Get-Date)",
                "No triggers found."
            ) | Out-File -FilePath $disableLog -Encoding UTF8

            @(
                "Enable Trigger script generated on $(Get-Date)",
                "No triggers found."
            ) | Out-File -FilePath $enableLog -Encoding UTF8

            Write-Host "Empty Disable/Enable Trigger SQL and logs generated for database '$db'." -ForegroundColor Cyan
            continue
        }

        $disableScript = "USE [$db];`nGO`n`n"
        $enableScript  = "USE [$db];`nGO`n`n"
        $triggerList   = New-Object System.Collections.ArrayList

        foreach ($row in $trigData) {
            $schema = "[" + $row.SchemaName + "]"
            $table  = "[" + $row.TableName + "]"
            $trig   = "[" + $row.TriggerName + "]"

            $disableScript += "DISABLE TRIGGER $schema.$trig ON $schema.$table;`r`nGO`r`n"
            $enableScript  += "ENABLE TRIGGER $schema.$trig ON $schema.$table;`r`nGO`r`n"

            $triggerList.Add("$($row.SchemaName).$($row.TriggerName)") | Out-Null
        }

        # Write SQL files
        $disableScript | Out-File -FilePath $disableFile -Encoding UTF8
        $enableScript  | Out-File -FilePath $enableFile -Encoding UTF8

        # Write logs
        @(
            "Disable Trigger script generated on $(Get-Date)",
            "Number of triggers: $($triggerList.Count)",
            "List:",
            $triggerList
        ) | Out-File -FilePath $disableLog -Encoding UTF8

        @(
            "Enable Trigger script generated on $(Get-Date)",
            "Number of triggers: $($triggerList.Count)",
            "List:",
            $triggerList
        ) | Out-File -FilePath $enableLog -Encoding UTF8

        Write-Host "Disable/Enable Trigger scripts and logs generated for database '$db'." -ForegroundColor Cyan
    }

    Write-Host "`nAll Trigger scripts and logs generated in folder: $triggerDir" -ForegroundColor Green
}





# -----------------------------
# Task 13: Generate & Execute TRUNCATE Tables

# -----------------------------
# Task 13: Generate & Execute TRUNCATE Tables (FK-safe, verification fixed)
# -----------------------------
if ($inputs -contains "13") {

    Write-Host "`nGenerateSQL Cleanup: Truncate Tables ..." -ForegroundColor Green

    $tableDir = Join-Path $workingDir "Tables"
    if (-not (Test-Path $tableDir)) { New-Item -Path $tableDir -ItemType Directory | Out-Null }

    $logDir = Join-Path $tableDir "LOG"
    if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory | Out-Null }

    function Clean-Name([string]$name) { return ($name -replace '\s+', '' -replace '[\uFEFF-\uFFFF]', '').Trim() }

    foreach ($db in $databases) {
        Write-Host "`nProcessing database '$db'..." -ForegroundColor Yellow

        if ($choice -eq "1") {
            $connString = "Server=$serverInstance;Database=$db;User ID=$username;Password=$plainPassword;Encrypt=False;TrustServerCertificate=True;"
        } else {
            $connString = "Server=$serverInstance;Database=$db;Trusted_Connection=True;"
        }

        $query = @"
WITH FKDeps AS (
    SELECT
        fk.parent_object_id AS ChildId,
        fk.referenced_object_id AS ParentId
    FROM sys.foreign_keys fk
)
SELECT t.name AS TableName,
       s.name AS SchemaName
FROM sys.tables t
INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
WHERE t.is_ms_shipped = 0
ORDER BY
    (SELECT COUNT(*) FROM FKDeps d WHERE d.ChildId = t.object_id) DESC,
    s.name, t.name;
"@

        try {
            $tableData = Invoke-Sqlcmd -ConnectionString $connString -Query $query
        } catch {
            Write-Host "ERROR: Cannot fetch table info from database '$db'. Skipping..." -ForegroundColor Red
            continue
        }

        $truncateFile = Join-Path $tableDir "TruncateTables_${db}.sql"
        $logFile      = Join-Path $logDir "TruncateTables_Execution_${db}.log"

        if (-not $tableData -or $tableData.Count -eq 0) {
            Write-Host "No user tables found in database '$db'. Generating empty SQL file..." -ForegroundColor Yellow
            "USE [$db];`r`nGO`r`n-- No tables found" | Out-File -FilePath $truncateFile -Encoding UTF8
            @(
                "Truncate Tables script generated on $(Get-Date)",
                "No tables found."
            ) | Out-File -FilePath $logFile -Encoding UTF8
            Write-Host "Empty Truncate Tables SQL and log generated for database '$db'." -ForegroundColor Cyan
            continue
        }

        $processedTables = @()
        $truncateScript = "USE [$db];`r`nGO`r`n`r`n"

        foreach ($tbl in $tableData) {
            $schema = Clean-Name $tbl.SchemaName
            $tableName = Clean-Name $tbl.TableName
            $processedTables += "$schema.$tableName"
            $truncateScript += "TRUNCATE TABLE [$schema].[$tableName];`r`nGO`r`n"
        }

        # Save TRUNCATE script
        "-- Truncate tables script for database '$db'" + "`r`n" | Out-File -FilePath $truncateFile -Encoding UTF8
        $truncateScript | Out-File -FilePath $truncateFile -Append -Encoding UTF8

        # Execution and log
        $logContent = @()
        $logContent += "Database: $db"
        $logContent += "Truncate executed on: $(Get-Date)"
        $logContent += "Number of tables to truncate: $($processedTables.Count)"

        $emptyTables = @()
        $nonEmptyTables = @()

        foreach ($fullTable in $processedTables) {
            $parts = $fullTable.Split(".")
            $schema = $parts[0]
            $tableName = $parts[1]
            $truncateCmd = "TRUNCATE TABLE [$schema].[$tableName];"

            try {
                Invoke-Sqlcmd -ConnectionString $connString -Query $truncateCmd -ErrorAction Stop
                $logContent += "Table: [$schema].[$tableName] | Truncate: SUCCESS"
            } catch {
                $logContent += "Table: [$schema].[$tableName] | Truncate: FAILED - $($_.Exception.Message)"
            }

            try {
                $verifyQuery = "SELECT COUNT(*) AS [RowCount] FROM [$schema].[$tableName];"
                $verifyResult = Invoke-Sqlcmd -ConnectionString $connString -Query $verifyQuery -ErrorAction Stop
                if ($verifyResult.RowCount -eq 0) {
                    $emptyTables += "$schema.$tableName"
                } else {
                    $nonEmptyTables += "$schema.$tableName ($($verifyResult.RowCount) rows)"
                }
            } catch {
                $nonEmptyTables += "$schema.$tableName (verification failed - $($_.Exception.Message))"
            }
        }

        $logContent += "`r`n=== Final Verification Summary ==="
        $logContent += "Tables empty: $($emptyTables.Count)"
        $logContent += "Tables not empty: $($nonEmptyTables.Count)"
        if ($nonEmptyTables.Count -gt 0) { $logContent += "Non-empty tables:"; $logContent += $nonEmptyTables }

        $logContent | Out-File -FilePath $logFile -Encoding UTF8
        Write-Host "Truncate tables log saved: $logFile" -ForegroundColor Green
    }

    Write-Host "`nAll TRUNCATE scripts and log files generated in folder: $tableDir" -ForegroundColor Green
}



 if ($inputs -contains "21") {

    Write-Host "`n[21] Pre-Migration: Drop Foreign Keys (Enhanced with Verification Summary)" -ForegroundColor Cyan

    $fkDir = Join-Path $workingDir "FK"
    if (-not (Test-Path $fkDir)) { New-Item -Path $fkDir -ItemType Directory | Out-Null }

    $logDir = Join-Path $fkDir "LOG"
    if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory | Out-Null }

    function Clean-Name([string]$name) {
        return ($name -replace '\s+', '' -replace '[\uFEFF-\uFFFF]', '').Trim()
    }

    foreach ($db in $databases) {
        Write-Host "`nProcessing database '$db'..." -ForegroundColor Yellow

        $fkFile = Join-Path $fkDir "DropFKs_${db}.sql"
        $logFile = Join-Path $logDir "DropFKs_Execution_$db.log"

        if ($choice -eq "1") {
            $connString = "Server=$serverInstance;Database=$db;User Id=$username;Password=$plainPassword;Encrypt=False;TrustServerCertificate=True;"
        }
        elseif ($choice -eq "2") {
            $connString = "Server=$serverInstance;Database=$db;Trusted_Connection=True;"
        }
        else {
            Write-Host "Invalid choice. Exiting."
            exit
        }

        if (-not (Test-Path $fkFile)) {
            Write-Host "ERROR: Drop FK script does not exist for database '$db': $fkFile" -ForegroundColor Red
            continue
        }

        $logContent = @()
        $logContent += "Database: $db"
        $logContent += "Drop Foreign Keys executed on: $(Get-Date)"
        $logContent += "Detailed FK drop results:"

        try {
            $fkCommands = Get-Content -Path $fkFile -Raw
            if (-not $fkCommands.Trim()) {
                Write-Host "Drop FK script is empty for database '$db'. No FKs to drop." -ForegroundColor Yellow
                $logContent += "No foreign keys found to drop."
                $logContent | Out-File -FilePath $logFile -Encoding UTF8
                continue
            }

            # Extract each ALTER TABLE ... DROP CONSTRAINT statement
            $fkLines = ($fkCommands -split "`r?`n") | Where-Object { $_ -match "ALTER TABLE .* DROP CONSTRAINT .*;" }

            $totalFKs = $fkLines.Count
            $droppedCount = 0
            $failedCount = 0

            foreach ($line in $fkLines) {
                if ($line -match "ALTER TABLE \[(.+?)\]\.\[(.+?)\] DROP CONSTRAINT \[(.+?)\];") {
                    $schema = Clean-Name $matches[1]
                    $table = Clean-Name $matches[2]
                    $fkName = Clean-Name $matches[3]

                    # Execute FK drop
                    try {
                        Invoke-Sqlcmd -ConnectionString $connString -Query $line -ErrorAction Stop
                        $dropResult = "SUCCESS"
                        $droppedCount++
                    } catch {
                        $dropResult = "FAILED - $_"
                        $failedCount++
                    }

                    # Verification: check if FK still exists
                    try {
                        $verifyQuery = @"
SELECT COUNT(*) AS FKExists
FROM sys.foreign_keys
WHERE name = '$fkName';
"@
                        $verify = Invoke-Sqlcmd -ConnectionString $connString -Query $verifyQuery
                        $verification = if ($verify.FKExists -eq 0) { "OK" } else { "FAILED" }
                    } catch {
                        $verification = "ERROR - $($_.Exception.Message)"
                    }

                    $logContent += "FK: $fkName | Table: $schema.$table | Drop: $dropResult -> Verification: $verification"
                }
            }

            Write-Host "Processed $totalFKs foreign key(s): $droppedCount dropped, $failedCount failed" -ForegroundColor Green

        } catch {
            Write-Host "ERROR executing Drop FK script for database '$db': $_" -ForegroundColor Red
            $logContent += "ERROR executing FK drop script: $_"
        }

        # ---------------- Final Verification with summary ----------------
        try {
            $remainingFKsQuery = @"
SELECT name, OBJECT_SCHEMA_NAME(parent_object_id) AS SchemaName, OBJECT_NAME(parent_object_id) AS TableName
FROM sys.foreign_keys;
"@
            $remainingFKs = Invoke-Sqlcmd -ConnectionString $connString -Query $remainingFKsQuery

            $remainingCount = $remainingFKs.Count
            $droppedCount = $totalFKs - $remainingCount

            Write-Host "`n=== Final FK Verification Summary ===" -ForegroundColor Cyan
            Write-Host "Total FKs in script: $totalFKs"
            Write-Host "FKs successfully dropped: $droppedCount"
            Write-Host "FKs remaining  on the database : $remainingCount"

            $logContent += ""
            $logContent += "=== Final FK Verification Summary ==="
            $logContent += "Total FKs in script: $totalFKs"
            $logContent += "FKs successfully dropped: $droppedCount"
            $logContent += "FKs remaining on the database: $remainingCount"

            if ($remainingCount -eq 0) {
                Write-Host "All foreign keys were successfully dropped." -ForegroundColor Green
                $logContent += "All foreign keys successfully dropped."
            } else {
                Write-Host "Remaining foreign keys in database '$db':" -ForegroundColor Red
                $logContent += "Remaining foreign keys ($remainingCount):"
                foreach ($fk in $remainingFKs) {
                    $fkName = Clean-Name $fk.name
                    $schemaName = Clean-Name $fk.SchemaName
                    $tableName = Clean-Name $fk.TableName
                    $logContent += " - $fkName on $schemaName.$tableName"
                    Write-Host " - $fkName on $schemaName.$tableName" -ForegroundColor Red
                }
            }
        } catch {
            Write-Host "ERROR during final FK verification for database '$db': $_" -ForegroundColor Red
            $logContent += "ERROR during final FK verification: $_"
        }

        # ---------------- Save log ----------------
        $logContent | Out-File -FilePath $logFile -Encoding UTF8
        Write-Host "Drop FKs log saved: $logFile" -ForegroundColor Cyan

        # ---------------- Check log for failures ----------------
        Write-Host "Checking for errors in the log..."
        $logLines = Get-Content -Path $logFile
        $hasErrors = $logLines | Where-Object { $_ -match "FAILED|ERROR|Could not find file" }

        if ($hasErrors) {
            Write-Host "Errors detected in FK drop process:" -ForegroundColor Red
            $hasErrors | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
        } else {
            Write-Host "Processed successfully. No errors found." -ForegroundColor Green
        }
    }
}



if ($inputs -contains "22") {
    Write-Host "`n[22] Pre-Migration: Disable Triggers (Enhanced with Line Mapping)" -ForegroundColor Cyan

    $triggerDir = Join-Path $workingDir "Triggers"
    if (-not (Test-Path $triggerDir)) { New-Item -Path $triggerDir -ItemType Directory | Out-Null }

    $logDir = Join-Path $triggerDir "LOG"
    if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory | Out-Null }

    function Clean-Name([string]$name) {
        return ($name -replace '\s+', '' -replace '[\uFEFF-\uFFFF]', '').Trim()
    }

    foreach ($db in $databases) {
        Write-Host "`nProcessing database '$db'..." -ForegroundColor Yellow

        $triggerFile = Join-Path $triggerDir "DisableTriggers_${db}.sql"
        $logFile = Join-Path $logDir "DisableTriggers_Execution_$db.log"

        if (-not (Test-Path $triggerFile)) {
            Write-Host "ERROR: Disable Triggers script does not exist for database '$db': $triggerFile" -ForegroundColor Red
            continue
        }

        # Authentication
        if ($choice -eq "1") {
            $connString = "Server=$serverInstance;Database=$db;User Id=$username;Password=$plainPassword;Encrypt=False;TrustServerCertificate=True;"
        }
        elseif ($choice -eq "2") {
            $connString = "Server=$serverInstance;Database=$db;Trusted_Connection=True;"
        }
        else {
            Write-Host "Invalid choice. Exiting."
            exit
        }

        # Initialize log content
        $logContent = @()
        $logContent += "Database: $db"
        $logContent += "Disable Triggers executed on: $(Get-Date)"
        $logContent += "Detailed trigger execution results (with source SQL line number):"

        try {
            $triggerLinesRaw = Get-Content -Path $triggerFile
            $triggerLinesIndexed = @()
            for ($i = 0; $i -lt $triggerLinesRaw.Count; $i++) {
                $line = $triggerLinesRaw[$i].Trim()
                if ($line -match "DISABLE TRIGGER .* ON .*;") {
                    $triggerLinesIndexed += @{ LineNumber = $i + 1; Sql = $line }
                }
            }

            $totalTriggers = $triggerLinesIndexed.Count
            $disabledCount = 0
            $failedCount = 0
            $triggerResults = @()

            foreach ($trEntry in $triggerLinesIndexed) {
                $lineNumber = $trEntry.LineNumber
                $sqlLine = $trEntry.Sql

                # Parse trigger info
                if ($sqlLine -match "DISABLE TRIGGER \[(?<schema>[^\]]+)\]\.\[(?<trigger>[^\]]+)\] ON \[(?<tblschema>[^\]]+)\]\.\[(?<tbl>[^\]]+)\];") {
                    $schema = Clean-Name $matches.schema
                    $triggerName = Clean-Name $matches.trigger
                    $table = Clean-Name $matches.tbl
                } elseif ($sqlLine -match "DISABLE TRIGGER (\S+) ON (\S+);") {
                    $triggerName = Clean-Name ($matches[1] -replace "[\[\]]","")
                    $tableFull = Clean-Name ($matches[2] -replace "[\[\]]","")
                    $schema = ($tableFull -split "\.")[0]
                    $table = ($tableFull -split "\.")[1]
                } else {
                    continue
                }

                # Execute the disable trigger line
                try {
                    Invoke-Sqlcmd -ConnectionString $connString -Query $sqlLine -ErrorAction Stop
                    $status = "SUCCESS"
                    $disabledCount++
                } catch {
                    $status = "FAILED - $_"
                    $failedCount++
                }

                # Verify trigger is disabled
                try {
                    $verifyQuery = "SELECT is_disabled FROM sys.triggers WHERE name = '$triggerName';"
                    $verifyResult = Invoke-Sqlcmd -ConnectionString $connString -Query $verifyQuery
                    $verification = if ($verifyResult.is_disabled -eq 1) { "OK" } else { "Trigger still enabled" }
                } catch {
                    $verification = "ERROR - $($_.Exception.Message)"
                }

                $triggerResults += "Line ${lineNumber}: Trigger: [${schema}].[${triggerName}] | Table: [${schema}].[${table}] | Disable: ${status} -> Verification: ${verification}"
            }

            $logContent += "Number of triggers processed: $totalTriggers"
            $logContent += $triggerResults

            # Final verification
            $remainingTriggersQuery = "SELECT name, OBJECT_SCHEMA_NAME(parent_id) AS SchemaName, OBJECT_NAME(parent_id) AS TableName FROM sys.triggers WHERE is_disabled = 0;"
            $remainingTriggers = Invoke-Sqlcmd -ConnectionString $connString -Query $remainingTriggersQuery
            $remainingCount = $remainingTriggers.Count

            Write-Host "`n=== Final Trigger Verification Summary ===" -ForegroundColor Cyan
            Write-Host "Total triggers in script: $totalTriggers"
            Write-Host "Triggers successfully disabled: $disabledCount"
            Write-Host "Triggers still enabled: $remainingCount"

            $logContent += ""
            $logContent += "=== Final Trigger Verification Summary ==="
            $logContent += "Total triggers in script: $totalTriggers"
            $logContent += "Triggers successfully disabled: $disabledCount"
            $logContent += "Triggers still enabled: $remainingCount"

            if ($remainingCount -eq 0) {
                Write-Host "All triggers are disabled in database '$db'. ✅" -ForegroundColor Green
                $logContent += "All triggers are disabled."
            } else {
                Write-Host "Remaining triggers still enabled:" -ForegroundColor Red
                $logContent += "Remaining triggers still enabled ($remainingCount):"
                foreach ($tr in $remainingTriggers) {
                    $trName = Clean-Name $tr.name
                    $schName = Clean-Name $tr.SchemaName
                    $tblName = Clean-Name $tr.TableName
                    Write-Host " - $trName on $schName.$tblName" -ForegroundColor Red
                    $logContent += " - $trName on $schName.$tblName"
                }
            }

        } catch {
            Write-Host "ERROR executing Disable Triggers script for database '$db': $_" -ForegroundColor Red
            $logContent += "ERROR executing Disable Triggers script: $_"
        }

        # Write log
        $logContent | Out-File -FilePath $logFile -Encoding UTF8
        Write-Host "Disable Triggers log saved: $logFile" -ForegroundColor Cyan

        # Check errors in log
        $logLines = Get-Content -Path $logFile
        $hasErrors = $logLines | Where-Object { $_ -match "FAILED|ERROR|Could not find file" }
        if ($hasErrors) {
            Write-Host "Errors detected in trigger disable process:" -ForegroundColor Red
            $hasErrors | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
        } else {
            Write-Host "Processed successfully. No errors found." -ForegroundColor Green
        }
    }
}



if ($inputs -contains "23") {
    Write-Host "`n[23] Pre-Migration: Delete Tables (FK-Safe + Sanitization + Verification Summary)" -ForegroundColor Cyan

    # Ensure directories exist
    $tableDir = Join-Path $workingDir "Tables"
    if (-not (Test-Path $tableDir)) { New-Item -Path $tableDir -ItemType Directory | Out-Null }

    $logDir = Join-Path $tableDir "LOG"
    if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory | Out-Null }

    foreach ($db in $databases) {

        Write-Host ""
        Write-Host "========================================="
        Write-Host "Processing database '$db'"
        Write-Host "========================================="

        # Build connection string
        if ($choice -eq "1") {
            $connString = "Server=$serverInstance;Database=$db;User Id=$username;Password=$plainPassword;Encrypt=False;TrustServerCertificate=True;"
        }
        elseif ($choice -eq "2") {
            $connString = "Server=$serverInstance;Database=$db;Trusted_Connection=True;"
        }
        else {
            Write-Host "Invalid choice. Exiting."
            exit
        }

        $logFile = Join-Path $logDir "DeleteTables_Execution_$db.log"

        # -------------------------------------------
        # Global sanitize function
        # -------------------------------------------
        function Clean-Name([string]$name) {
            return ($name -replace '\s+', '' -replace '[\uFEFF-\uFFFF]', '').Trim()
        }

        # -------------------------------------------
        # STEP 1 — Load FK relationships and tables
        # -------------------------------------------
        Write-Host "Loading FK relationships..." -ForegroundColor Yellow

        $fkQuery = @"
SELECT 
    FKTable = QUOTENAME(SCHEMA_NAME(fk_tab.schema_id)) + '.' + QUOTENAME(fk_tab.name),
    PKTable = QUOTENAME(SCHEMA_NAME(pk_tab.schema_id)) + '.' + QUOTENAME(pk_tab.name)
FROM sys.foreign_keys fk
JOIN sys.tables fk_tab ON fk_tab.object_id = fk.parent_object_id
JOIN sys.tables pk_tab ON pk_tab.object_id = fk.referenced_object_id
WHERE fk_tab.is_ms_shipped = 0 AND pk_tab.is_ms_shipped = 0;
"@

        $fkRows = Invoke-Sqlcmd -ConnectionString $connString -Query $fkQuery -ErrorAction Stop

        Write-Host "Loading table list..." -ForegroundColor Yellow
        $tableQuery = "SELECT QUOTENAME(SCHEMA_NAME(schema_id)) + '.' + QUOTENAME(name) AS Tbl FROM sys.tables WHERE is_ms_shipped = 0;"
        $allTablesRaw = Invoke-Sqlcmd -ConnectionString $connString -Query $tableQuery | Select-Object -ExpandProperty Tbl

        # Sanitize table names
        $allTables = $allTablesRaw | ForEach-Object { Clean-Name $_ }

        # -------------------------------------------
        # STEP 2 — Build dependency graph
        # -------------------------------------------
        Write-Host "Computing FK-safe delete order..." -ForegroundColor Yellow

        $graph = @{}
        foreach ($tbl in $allTables) { $graph[$tbl] = @() }

        foreach ($row in $fkRows) {
            $FK = Clean-Name $row.FKTable
            $PK = Clean-Name $row.PKTable
            if ($graph.ContainsKey($FK)) { $graph[$FK] += $PK }
        }

        # -------------------------------------------
        # STEP 3 — Topological sort
        # -------------------------------------------
        $visited = @{}
        $sorted = New-Object System.Collections.Generic.List[string]

        function Visit([string]$node) {
            if ($visited[$node] -eq "TEMP") { throw "Cycle detected at $node" }
            if ($visited[$node] -eq "PERM") { return }

            $visited[$node] = "TEMP"
            foreach ($dep in $graph[$node]) { Visit $dep }
            $visited[$node] = "PERM"
            $sorted.Add($node)
        }

        foreach ($t in $allTables) { Visit $t }

        # Reverse topological order → child tables first
        $deleteOrder = $sorted.ToArray()
        [array]::Reverse($deleteOrder)

        Write-Host "`nDELETE execution order (child → parent):" -ForegroundColor Cyan
        $deleteOrder | ForEach-Object { Write-Host " - $_" }

        # Confirm
        do {
            $confirm = Read-Host "Proceed with deletion for '$db'? (Y/N)"
            $confirm = $confirm.Trim().ToUpper()
        } until ($confirm -in @("Y","N"))

        if ($confirm -eq "N") {
            Write-Host "Skipping '$db'" -ForegroundColor Yellow
            continue
        }

        # -------------------------------------------
        # STEP 4 — Execute DELETE FROM
        # -------------------------------------------
        $processedTables = @()
        $detailedLog = @()

        foreach ($tbl in $deleteOrder) {
            $cleanTbl = Clean-Name $tbl
            $deleteQuery = "DELETE FROM $cleanTbl;"

            try {
                Invoke-Sqlcmd -ConnectionString $connString -Query $deleteQuery -ErrorAction Stop
                $processedTables += $cleanTbl
                $detailedLog += "Table: $cleanTbl | Delete: SUCCESS"
            }
            catch {
                $err = $_.Exception.Message
                $processedTables += $cleanTbl
                $detailedLog += "Table: $cleanTbl | Delete: FAILED - $err"
                Write-Host "ERROR deleting $cleanTbl → $err" -ForegroundColor Red
            }
        }

        # -------------------------------------------
        # STEP 5 — Enhanced Verification with summary
        # -------------------------------------------
        Write-Host "`nFINAL VERIFICATION — Ensuring tables are empty..." -ForegroundColor Cyan

        $emptyCount = 0
        $nonEmptyCount = 0
        $nonEmptyTables = @()
        $verificationResults = @()

        foreach ($tbl in $processedTables) {
            $cleanTbl = Clean-Name $tbl
            $verifyQuery = "SELECT COUNT(*) AS [RowCount] FROM $cleanTbl;"

            try {
                $result = Invoke-Sqlcmd -ConnectionString $connString -Query $verifyQuery -ErrorAction Stop
                $rowCount = $result.RowCount

                if ($rowCount -eq 0) {
                    $verificationResults += "Table: $cleanTbl | Verification: OK (0 rows)"
                    $emptyCount++
                } else {
                    $verificationResults += "Table: $cleanTbl | Verification: FAILED - $rowCount rows remain"
                    $nonEmptyCount++
                    $nonEmptyTables += "$cleanTbl ($rowCount rows)"
                }
            }
            catch {
                $verificationResults += "Table: $cleanTbl | Verification: ERROR - $($_.Exception.Message)"
                $nonEmptyCount++
                $nonEmptyTables += "$cleanTbl (ERROR)"
            }
        }

        # Print summary
        Write-Host "`n=== Verification Summary ===" -ForegroundColor Cyan
        Write-Host "Total tables processed: $($processedTables.Count)"
        Write-Host "Empty tables: $emptyCount"
        Write-Host "Non-empty tables: $nonEmptyCount"

        if ($nonEmptyTables.Count -gt 0) {
            Write-Host "`nList of non-empty tables:" -ForegroundColor Red
            $nonEmptyTables | ForEach-Object { Write-Host " - $_" }
        }

        # -------------------------------------------
        # STEP 6 — Logging
        # -------------------------------------------
        $logContent = @()
        $logContent += "Database: $db"
        $logContent += "Executed: $(Get-Date)"
        $logContent += "Tables processed: $($processedTables.Count)"
        $logContent += ""
        $logContent += "=== DELETE RESULTS ==="
        $logContent += $detailedLog
        $logContent += ""
        $logContent += "=== VERIFICATION RESULTS ==="
        $logContent += $verificationResults
        $logContent += ""
        $logContent += "=== VERIFICATION SUMMARY ==="
        $logContent += "Empty tables: $emptyCount"
        $logContent += "Non-empty tables: $nonEmptyCount"
        if ($nonEmptyTables.Count -gt 0) {
            $logContent += "List of non-empty tables:"
            $logContent += $nonEmptyTables
        }

        $logContent | Out-File -FilePath $logFile -Encoding UTF8

        Write-Host "`nDelete Tables log saved: $logFile" -ForegroundColor Green


	
		Write-Host " Check if  errors on $logFile ... "
	
	
	# --- Read the log file ---
$logLines = Get-Content -Path $logFile

# Flag to track if any errors were found
$hasErrors = $false

foreach ($line in $logLines) {
    if ($line -match "FAILED" -or $line -match "Could not find file") {
        Write-Host $line -ForegroundColor Red
        $hasErrors = $true
    }
}

 

   
	
	

        # Detect errors
        if ($logContent -match "FAILED|ERROR") {
            Write-Host "Errors detected! See log file." -ForegroundColor Red
        } else {
            Write-Host "Processed successfully. No errors found." -ForegroundColor Green
        }

    } # foreach DB

    Write-Host "`nAll DELETE scripts and logs are in: $tableDir" -ForegroundColor Green
}



# -----------------------------

# Block 31: Enable Foreign Keys

# -----------------------------
# -----------------------------
# Task 31: Enable Foreign Keys
# -----------------------------
if ($inputs -contains "31") {
    Write-Host "`n[31] Pre-Migration: Enable Foreign Keys (Enhanced)" -ForegroundColor Cyan

    $fkDir = Join-Path $workingDir "FK"
    $logDir = Join-Path $fkDir "LOG"
    if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory | Out-Null }

    function Clean-Name([string]$name) { return ($name -replace '\s+', '' -replace '[\uFEFF-\uFFFF]', '').Trim() }

    foreach ($db in $databases) {
        Write-Host "`nProcessing database '$db'..." -ForegroundColor Yellow

        if ($choice -eq "1") {
            $connString = "Server=$serverInstance;Database=$db;User Id=$username;Password=$plainPassword;Encrypt=False;TrustServerCertificate=True;"
        } elseif ($choice -eq "2") {
            $connString = "Server=$serverInstance;Database=$db;Trusted_Connection=True;"
        } else {
            Write-Host "Invalid choice. Exiting."
            exit
        }

        $fkFile = Join-Path $fkDir "CreateFKs_${db}.sql"
        $logFile = Join-Path $logDir "CreateFKs_Execution_$db.log"

        if (-not (Test-Path $fkFile)) {
            Write-Host "ERROR: FK script missing for database '$db': $fkFile" -ForegroundColor Red
            continue
        }

        $fkScriptRaw = Get-Content -Path $fkFile
        $fkBatches = @()
        for ($i = 0; $i -lt $fkScriptRaw.Count; $i++) {
            $line = $fkScriptRaw[$i].Trim()
            if ($line -match "ADD CONSTRAINT") {
                $fkBatches += @{ LineNumber = $i + 1; Sql = $line }
            }
        }

        $totalFKs = $fkBatches.Count
        $enabledCount = 0
        $failedCount = 0
        $logDetails = @()

        foreach ($fkEntry in $fkBatches) {
            $lineNumber = $fkEntry.LineNumber
            $sqlLine = $fkEntry.Sql
            if ($sqlLine -match "ADD CONSTRAINT \[(?<fkname>[^\]]+)\]") { $fkName = Clean-Name $matches['fkname'] } else { $fkName = "UNKNOWN" }

            # Remove USE statements
            $batchClean = ($sqlLine -split "`r?`n" | Where-Object { $_ -notmatch "^USE\s+\[.*\];" }) -join "`r`n"

            # Execute batch
            try {
                Invoke-Sqlcmd -ConnectionString $connString -Query $batchClean -ErrorAction Stop
                $status = "SUCCESS"
                $enabledCount++
            } catch {
                $status = "FAILED - $_"
                $failedCount++
            }

            # Verification
            try {
                $verify = Invoke-Sqlcmd -ConnectionString $connString -Query "SELECT name FROM sys.foreign_keys WHERE name = '$fkName'" | Select-Object -ExpandProperty name
                $verifyStatus = if ($verify) { "OK" } else { "NOT FOUND" }
            } catch {
                $verifyStatus = "ERROR"
            }

            $logDetails += "Line ${lineNumber}: FK: [$fkName] | Enable: ${status} -> Verification: ${verifyStatus}"
        }

        # Final verification: any FK not created?
        $remainingFKsQuery = "SELECT name, OBJECT_SCHEMA_NAME(parent_object_id) AS SchemaName, OBJECT_NAME(parent_object_id) AS TableName FROM sys.foreign_keys;"
        $remainingFKs = Invoke-Sqlcmd -ConnectionString $connString -Query $remainingFKsQuery
        $remainingCount = $remainingFKs.Count

        Write-Host "`n=== Final FK Verification Summary ===" -ForegroundColor Cyan
        Write-Host "Total FKs in script: $totalFKs"
        Write-Host "FKs successfully enabled: $enabledCount"
        Write-Host "FKs remaining (not created): $remainingCount"
        if ($remainingCount -gt 0) {
            foreach ($fk in $remainingFKs) {
                Write-Host " - $($fk.name) on $($fk.SchemaName).$($fk.TableName)" -ForegroundColor Red
            }
        }

        # Write log
        $logContent = @(
            "Database: $db",
            "Enable Foreign Keys executed on: $(Get-Date)",
            "Total FKs in script: $totalFKs",
            "FKs successfully enabled: $enabledCount",
            "FKs remaining (not created): $remainingCount",
            "Detailed FK execution results:"
        )
        $logContent += $logDetails
        $logContent | Out-File -FilePath $logFile -Encoding UTF8
        Write-Host "FK enable log saved: $logFile" -ForegroundColor Green
    }
}

# -----------------------------
# Task 32: Enable Triggers
# -----------------------------
if ($inputs -contains "32") {
    Write-Host "`n[32] Pre-Migration: Enable Triggers (Enhanced)" -ForegroundColor Cyan

    $triggerDir = Join-Path $workingDir "Triggers"
    $logDir = Join-Path $triggerDir "LOG"
    if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory | Out-Null }

    function Clean-Name([string]$name) { return ($name -replace '\s+', '' -replace '[\uFEFF-\uFFFF]', '').Trim() }

    foreach ($db in $databases) {
        Write-Host "`nProcessing database '$db'..." -ForegroundColor Yellow

        if ($choice -eq "1") {
            $connString = "Server=$serverInstance;Database=$db;User Id=$username;Password=$plainPassword;Encrypt=False;TrustServerCertificate=True;"
        } elseif ($choice -eq "2") {
            $connString = "Server=$serverInstance;Database=$db;Trusted_Connection=True;"
        } else {
            Write-Host "Invalid choice. Exiting."
            exit
        }

        $triggerFile = Join-Path $triggerDir "EnableTriggers_${db}.sql"
        $logFile = Join-Path $logDir "EnableTriggers_Execution_$db.log"

        if (-not (Test-Path $triggerFile)) {
            Write-Host "ERROR: Trigger script does not exist for database '$db': $triggerFile" -ForegroundColor Red
            continue
        }

        $triggerLinesRaw = Get-Content -Path $triggerFile
        $triggerLinesIndexed = @()
        for ($i = 0; $i -lt $triggerLinesRaw.Count; $i++) {
            $line = $triggerLinesRaw[$i].Trim()
            if ($line -match "ENABLE TRIGGER .* ON .*;") { $triggerLinesIndexed += @{ LineNumber = $i + 1; Sql = $line } }
        }

        $totalTriggers = $triggerLinesIndexed.Count
        $enabledCount = 0
        $failedCount = 0
        $triggerResults = @()

        foreach ($trEntry in $triggerLinesIndexed) {
            $lineNumber = $trEntry.LineNumber
            $sqlLine = $trEntry.Sql

            if ($sqlLine -match "ENABLE TRIGGER \[(?<schema>[^\]]+)\]\.\[(?<trigger>[^\]]+)\] ON \[(?<tblschema>[^\]]+)\]\.\[(?<tbl>[^\]]+)\];") {
                $schema = Clean-Name $matches.schema
                $triggerName = Clean-Name $matches.trigger
                $table = Clean-Name $matches.tbl
            } elseif ($sqlLine -match "ENABLE TRIGGER (\S+) ON (\S+);") {
                $triggerName = Clean-Name ($matches[1] -replace "[\[\]]","")
                $tableFull = Clean-Name ($matches[2] -replace "[\[\]]","")
                $schema = ($tableFull -split "\.")[0]
                $table = ($tableFull -split "\.")[1]
            } else { continue }

            # Execute enable trigger
            try {
                Invoke-Sqlcmd -ConnectionString $connString -Query $sqlLine -ErrorAction Stop
                $status = "SUCCESS"
                $enabledCount++
            } catch {
                $status = "FAILED - $_"
                $failedCount++
            }

            # Verify
            try {
                $verifyQuery = "SELECT is_disabled FROM sys.triggers WHERE name = '$triggerName';"
                $verifyResult = Invoke-Sqlcmd -ConnectionString $connString -Query $verifyQuery
                $verification = if ($verifyResult.is_disabled -eq 0) { "OK" } else { "Trigger still disabled" }
            } catch {
                $verification = "ERROR - $($_.Exception.Message)"
            }

            $triggerResults += "Line ${lineNumber}: Trigger: [${schema}].[${triggerName}] | Table: [${schema}].[${table}] | Enable: ${status} -> Verification: ${verification}"
        }

        # Final verification
        $remainingTriggersQuery = "SELECT name, OBJECT_SCHEMA_NAME(parent_id) AS SchemaName, OBJECT_NAME(parent_id) AS TableName FROM sys.triggers WHERE is_disabled = 1;"
        $remainingTriggers = Invoke-Sqlcmd -ConnectionString $connString -Query $remainingTriggersQuery
        $remainingCount = $remainingTriggers.Count

        Write-Host "`n=== Final Trigger Verification Summary ===" -ForegroundColor Cyan
        Write-Host "Total triggers in script: $totalTriggers"
        Write-Host "Triggers successfully enabled: $enabledCount"
        Write-Host "Triggers remaining disabled: $remainingCount"
        if ($remainingCount -gt 0) {
            foreach ($tr in $remainingTriggers) {
                Write-Host " - $($tr.name) on $($tr.SchemaName).$($tr.TableName)" -ForegroundColor Red
            }
        }

        # Write log
        $logContent = @(
            "Database: $db",
            "Enable Triggers executed on: $(Get-Date)",
            "Total triggers in script: $totalTriggers",
            "Triggers successfully enabled: $enabledCount",
            "Triggers remaining disabled: $remainingCount",
            "Detailed trigger execution results:"
        )
        $logContent += $triggerResults
        $logContent | Out-File -FilePath $logFile -Encoding UTF8
        Write-Host "Enable Triggers log saved: $logFile" -ForegroundColor Green
    }
}

if ($inputs -contains "4") {

    foreach ($db in $databases) {

        Write-Host "`nProcessing validation for database '${db}'..." -ForegroundColor Cyan

        # Define log directories
        $logDir      =   $workingDir 
        $fkLogDir    = Join-Path $logDir "FK\LOG"
        $trigLogDir  = Join-Path $logDir "Triggers\LOG"
        $tableLogDir = Join-Path $logDir "Tables\LOG"

        # Define log files
        $fkDropLog      = Join-Path $fkLogDir "DropFKs_Execution_${db}.log"
        $fkEnableLog    = Join-Path $fkLogDir "CreateFKs_Execution_${db}.log"
        $trigDisableLog = Join-Path $trigLogDir "DisableTriggers_${db}.log"
        $trigEnableLog  = Join-Path $trigLogDir "EnableTriggers_${db}.log"
        $tableLog       = Join-Path $tableLogDir "TruncateTables_${db}.log"

        # ----- Check logs for errors -----
        $logFiles = @(
            @{ Label="Triggers Disabled"; Path=$trigDisableLog },
            @{ Label="Triggers Enabled"; Path=$trigEnableLog },
            @{ Label="Tables Truncated"; Path=$tableLog },
            @{ Label="FKs Dropped"; Path=$fkDropLog },
            @{ Label="FKs Enabled"; Path=$fkEnableLog }
        )

        $errorsSummary = @{}
        foreach ($log in $logFiles) {
            if (Test-Path $log.Path) {
                $lines = Get-Content -Path $log.Path
                $errorLines = $lines | Where-Object { $_ -match "FAILED" -or $_ -match "Could not find file" }
                if ($errorLines.Count -eq 0) {
                    $errorsSummary[$log.Label] = "No Errors"
                } else {
                    $errorsSummary[$log.Label] = "Errors found"
                }
            } else {
                $errorsSummary[$log.Label] = "Log missing"
            }
        }

        # ----- Database information -----
        $rowCountsQuery = @"
SELECT 
    s.name AS SchemaName,
    t.name AS TableName,
    ISNULL(SUM(p.rows),0) AS TableRows
FROM sys.tables t
JOIN sys.schemas s ON t.schema_id = s.schema_id
LEFT JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0,1)
GROUP BY s.name, t.name
ORDER BY s.name, t.name;
"@

        try {
            $tables = Invoke-Sqlcmd -ServerInstance $serverInstance -Database $db -Query $rowCountsQuery -ErrorAction Stop
            $emptyTables    = $tables | Where-Object { $_.TableRows -eq 0 }
            $nonEmptyTables = $tables | Where-Object { $_.TableRows -gt 0 }
        } catch {
            $errMsg = $_.Exception.Message
            Write-Warning "SQL Error while retrieving table row counts for ${db}: ${errMsg}"
            $tables = @(); $emptyTables=@(); $nonEmptyTables=@()
        }

        # ----- Triggers -----
        $triggerQuery = @"
SELECT name, OBJECTPROPERTY(object_id, 'ExecIsTriggerDisabled') AS is_disabled 
FROM sys.objects 
WHERE type = 'TR';
"@

        try {
            $triggers = Invoke-Sqlcmd -ServerInstance $serverInstance -Database $db -Query $triggerQuery -ErrorAction Stop
            $enabledTriggers  = $triggers | Where-Object { $_.is_disabled -eq 0 }
            $disabledTriggers = $triggers | Where-Object { $_.is_disabled -eq 1 }
        } catch {
            $enabledTriggers=@(); $disabledTriggers=@()
            Write-Warning "Failed to retrieve triggers for ${db}: $_"
        }

        # ----- Foreign Keys -----
        $foreignKeysQuery = @"
SELECT fk.name AS FKName, t.name AS TableName
FROM sys.foreign_keys fk
JOIN sys.tables t ON fk.parent_object_id = t.object_id
ORDER BY t.name, fk.name;
"@

        try {
            $foreignKeys = Invoke-Sqlcmd -ServerInstance $serverInstance -Database $db -Query $foreignKeysQuery -ErrorAction Stop
        } catch {
            $foreignKeys=@()
            Write-Warning "Failed to retrieve foreign keys for ${db}: $_"
        }

        # ----- Output Builder -----
        $output = New-Object System.Text.StringBuilder
        $output.AppendLine("===== Pre/Post-Migration Validation Summary =====") | Out-Null
        $output.AppendLine("Database: $db") | Out-Null

        # ----- Print log errors -----
        foreach ($log in $logFiles) {
            $label = $log.Label
            $errorText = if ($errorsSummary[$label] -eq "No Errors") { "0" } else { "Check Log: $($log.Path)" }
            Write-Host ("{0} Errors: {1}" -f $label, $errorText)
            $output.AppendLine(("{0} Errors: {1}" -f $label, $errorText)) | Out-Null
        }

        # ----- Tables -----
        Write-Host "`nTables empty: $($emptyTables.Count)"
        $output.AppendLine("Tables empty: $($emptyTables.Count)") | Out-Null
        Write-Host "Tables not empty: $($nonEmptyTables.Count)"
        $output.AppendLine("Tables not empty: $($nonEmptyTables.Count)") | Out-Null
        if ($nonEmptyTables.Count -gt 0) {
            foreach ($t in $nonEmptyTables) {
                Write-Host " - $($t.TableName) ($($t.TableRows) rows)"
                $output.AppendLine(" - $($t.TableName) ($($t.TableRows) rows)") | Out-Null
            }
        }

        # ----- Triggers -----
        Write-Host "`nTriggers Enabled: $($enabledTriggers.Count)"
        $output.AppendLine("Triggers Enabled: $($enabledTriggers.Count)") | Out-Null
        if ($enabledTriggers.Count -gt 0) {
            foreach ($tr in $enabledTriggers) {
                Write-Host " - $($tr.name)"
                $output.AppendLine(" - $($tr.name)") | Out-Null
            }
        }

        Write-Host "Triggers Disabled: $($disabledTriggers.Count)"
        $output.AppendLine("Triggers Disabled: $($disabledTriggers.Count)") | Out-Null
        if ($disabledTriggers.Count -gt 0) {
            foreach ($tr in $disabledTriggers) {
                Write-Host " - $($tr.name)"
                $output.AppendLine(" - $($tr.name)") | Out-Null
            }
        }

        # ----- Foreign Keys -----
        Write-Host "`nForeign Keys: $($foreignKeys.Count)"
        $output.AppendLine("Foreign Keys: $($foreignKeys.Count)") | Out-Null
        if ($foreignKeys.Count -gt 0) {
            foreach ($fk in $foreignKeys) {
                Write-Host " - $($fk.FKName) (Table: $($fk.TableName))"
                $output.AppendLine(" - $($fk.FKName) (Table: $($fk.TableName))") | Out-Null
            }
        }

        # ----- Summary Table -----
        $output.AppendLine("===== Database Summary =====") | Out-Null
        $output.AppendLine(("Database           : {0}" -f $db)) | Out-Null
        $output.AppendLine(("Total Tables       : {0}" -f $tables.Count)) | Out-Null
        $output.AppendLine(("Tables Empty       : {0}" -f $emptyTables.Count)) | Out-Null
        $output.AppendLine(("Tables Not Empty   : {0}" -f $nonEmptyTables.Count)) | Out-Null
        $output.AppendLine(("Triggers Enabled   : {0}" -f $enabledTriggers.Count)) | Out-Null
        $output.AppendLine(("Triggers Disabled  : {0}" -f $disabledTriggers.Count)) | Out-Null
        $output.AppendLine(("Foreign Keys       : {0}" -f $foreignKeys.Count)) | Out-Null
        $output.AppendLine("=================================") | Out-Null

        Write-Host "`n===== Database Summary ====="
        Write-Host ("Database           : {0}" -f $db)
        Write-Host ("Total Tables       : {0}" -f $tables.Count)
        Write-Host ("Tables Empty       : {0}" -f $emptyTables.Count)
        Write-Host ("Tables Not Empty   : {0}" -f $nonEmptyTables.Count)
        Write-Host ("Triggers Enabled   : {0}" -f $enabledTriggers.Count)
        Write-Host ("Triggers Disabled  : {0}" -f $disabledTriggers.Count)
        Write-Host ("Foreign Keys       : {0}" -f $foreignKeys.Count)
        Write-Host "================================="

        # ----- Export TXT and HTML -----
        $txtPath  = Join-Path $workingDir "${db}_ValidationReport.txt"
        $htmlPath = Join-Path $workingDir "${db}_ValidationReport.html"

        # TXT
        $output.ToString() | Out-File -FilePath $txtPath -Encoding UTF8

        # HTML
        $htmlContent = "<html><head><title>Validation Report - ${db}</title></head><body><pre>" +
                        ($output.ToString() -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;') +
                        "</pre></body></html>"
        $htmlContent | Out-File -FilePath $htmlPath -Encoding UTF8

        Write-Host "`nReport exported to TXT: $txtPath" -ForegroundColor Green
        Write-Host "Report exported to HTML: $htmlPath" -ForegroundColor Green
    }
}





 if ($inputs -contains "5") {

    # ===== Output folder = user's working directory =====
    $reportDir = $workingDir
    if (-not (Test-Path $reportDir)) { New-Item -ItemType Directory -Path $reportDir | Out-Null }

    # Prepare storage for summary and detailed reports
    $summaryTable = @()
    $detailedTxt  = @()
    $detailedHtml = @()
    $tablesByDb   = @{}
    $fksByDb      = @{}
    $triggersByDb = @{}
    $truncateInfoByDb = @{}  # Stores tables empty / not empty
    $fkErrorsByDb = @{}      # Stores FK drop/enable errors
    $triggerErrorsByDb = @{} # Stores trigger enable/disable errors

    $detailedHtml += "<html><head><title>Database Inventory Report</title></head><body>"
    $detailedHtml += "<h1>Database Inventory Report</h1>"

    foreach ($db in $databases) {

        Write-Host "`nProcessing database: $db" -ForegroundColor Cyan

        # ===== Tables =====
        $tableQuery = @"
SELECT t.object_id,
       t.name AS TableName,
       SUM(p.rows) AS TotalRows
FROM sys.tables t
LEFT JOIN sys.partitions p ON t.object_id = p.object_id AND p.index_id IN (0,1)
GROUP BY t.object_id, t.name
ORDER BY t.name;
"@
        try {
            $tables = Invoke-Sqlcmd -ServerInstance $serverInstance -Database $db -Query $tableQuery -ErrorAction Stop
        } catch {
            Write-Host ("ERROR: Failed to retrieve tables for " + $db + ": " + $_.Exception.Message) -ForegroundColor Red
            $tables = @()
        }
        $tablesByDb[$db] = $tables

        $tableCount = $tables.Count
        $rowCount   = if ($tables.Count -gt 0) { ($tables | Measure-Object -Property TotalRows -Sum).Sum } else { 0 }

        # Determine empty vs non-empty tables
        $emptyTables    = @()
        $nonEmptyTables = @()
        foreach ($t in $tables) {
            if ($t.TotalRows -eq 0) { $emptyTables += $t.TableName } else { $nonEmptyTables += "$($t.TableName) ($($t.TotalRows) rows)" }
        }
        $truncateInfoByDb[$db] = @{ Empty = $emptyTables; NotEmpty = $nonEmptyTables }

        # ===== Foreign Keys =====
        $fkQuery = @"
SELECT fk.name AS FKName,
       t.name AS TableName
FROM sys.foreign_keys fk
JOIN sys.tables t ON fk.parent_object_id = t.object_id
ORDER BY t.name, fk.name;
"@
        try {
            $fks = Invoke-Sqlcmd -ServerInstance $serverInstance -Database $db -Query $fkQuery -ErrorAction Stop
        } catch {
            Write-Host ("ERROR: Failed to retrieve foreign keys for " + $db + ": " + $_.Exception.Message) -ForegroundColor Red
            $fks = @()
        }
        $fksByDb[$db] = $fks
        $fkCount = if ($null -eq $fks -or $fks.Count -eq 0) { 0 } else { $fks.Count }

        # Optional: previous FK errors (if available)
        $fkErrors = if ($fkErrorsByDb.ContainsKey($db)) { $fkErrorsByDb[$db] } else { @() }

        # ===== Triggers =====
        $triggerQuery = @"
SELECT name,
       OBJECTPROPERTY(object_id, 'ExecIsTriggerDisabled') AS is_disabled
FROM sys.objects
WHERE type = 'TR';
"@
        try {
            $triggers = Invoke-Sqlcmd -ServerInstance $serverInstance -Database $db -Query $triggerQuery -ErrorAction Stop
        } catch {
            Write-Host ("ERROR: Failed to retrieve triggers for " + $db + ": " + $_.Exception.Message) -ForegroundColor Red
            $triggers = @()
        }
        $triggersByDb[$db] = $triggers
        $trigEnabled  = $triggers | Where-Object { $_.is_disabled -eq 0 }
        $trigDisabled = $triggers | Where-Object { $_.is_disabled -eq 1 }

        # Optional: previous trigger errors (if available)
        $trigErrors = if ($triggerErrorsByDb.ContainsKey($db)) { $triggerErrorsByDb[$db] } else { @() }

        # ===== Summary =====
        $summaryTable += [PSCustomObject]@{
            Database          = $db
            Tables            = $tableCount
            TotalRows         = $rowCount
            TablesEmpty       = $emptyTables.Count
            TablesNotEmpty    = $nonEmptyTables.Count
            ForeignKeys       = $fkCount
            FKErrors          = $fkErrors.Count
            TriggersEnabled   = $trigEnabled.Count
            TriggersDisabled  = $trigDisabled.Count
            TriggerErrors     = $trigErrors.Count
        }

        # ===== Detailed TXT =====
        $detailedTxt += "Database: $db"
        $detailedTxt += "Summary:"
        $detailedTxt += " - Total Tables       : $tableCount"
        $detailedTxt += " - Total Rows         : $rowCount"
        $detailedTxt += " - Tables Empty       : $($emptyTables.Count)"
        $detailedTxt += " - Tables Not Empty   : $($nonEmptyTables.Count)"
        $detailedTxt += " - Foreign Keys       : $fkCount"
        if ($fkErrors.Count -gt 0) { $detailedTxt += " - FK Errors          : $($fkErrors.Count) | " + ($fkErrors -join ", ") }
        $detailedTxt += " - Triggers Enabled   : $($trigEnabled.Count)"
        $detailedTxt += " - Triggers Disabled  : $($trigDisabled.Count)"
        if ($trigErrors.Count -gt 0) { $detailedTxt += " - Trigger Errors     : $($trigErrors.Count) | " + ($trigErrors -join ", ") }

        # Tables list
        $detailedTxt += "`nTables Detail:"
        foreach ($t in $tables) { $detailedTxt += " - $($t.TableName) : $($t.TotalRows) rows" }

        # Foreign Keys list with table
        $detailedTxt += "`nForeign Keys Detail:"
        foreach ($fk in $fks) { $detailedTxt += " - $($fk.FKName) (Table: $($fk.TableName))" }

        # Triggers list
        $detailedTxt += "`nTriggers Detail:"
        foreach ($tr in $triggers) {
            $status = if ($tr.is_disabled -eq 0) { "ENABLED" } else { "DISABLED" }
            $detailedTxt += " - $($tr.name) [$status]"
        }
        $detailedTxt += "`n----------------------------------------------------`n"

        # ===== Detailed HTML =====
        $detailedHtml += "<h2>Database: $db</h2>"
        $detailedHtml += "<h3>Summary</h3><ul>"
        $detailedHtml += "<li>Total Tables       : $tableCount</li>"
        $detailedHtml += "<li>Total Rows         : $rowCount</li>"
        $detailedHtml += "<li>Tables Empty       : $($emptyTables.Count)</li>"
        $detailedHtml += "<li>Tables Not Empty   : $($nonEmptyTables.Count)</li>"
        $detailedHtml += "<li>Foreign Keys       : $fkCount</li>"
        if ($fkErrors.Count -gt 0) { $detailedHtml += "<li>FK Errors         : $($fkErrors.Count) | " + ($fkErrors -join ", ") + "</li>" }
        $detailedHtml += "<li>Triggers Enabled   : $($trigEnabled.Count)</li>"
        $detailedHtml += "<li>Triggers Disabled  : $($trigDisabled.Count)</li>"
        if ($trigErrors.Count -gt 0) { $detailedHtml += "<li>Trigger Errors    : $($trigErrors.Count) | " + ($trigErrors -join ", ") + "</li>" }
        $detailedHtml += "</ul>"

        # Tables
        $detailedHtml += "<h3>Tables Detail</h3><ul>"
        foreach ($t in $tables) { $detailedHtml += "<li>$($t.TableName) : $($t.TotalRows) rows</li>" }
        $detailedHtml += "</ul>"

        # Foreign Keys
        $detailedHtml += "<h3>Foreign Keys Detail</h3><ul>"
        foreach ($fk in $fks) { $detailedHtml += "<li>$($fk.FKName) (Table: $($fk.TableName))</li>" }
        $detailedHtml += "</ul>"

        # Triggers
        $detailedHtml += "<h3>Triggers Detail</h3><ul>"
        foreach ($tr in $triggers) {
            $status = if ($tr.is_disabled -eq 0) { "ENABLED" } else { "DISABLED" }
            $detailedHtml += "<li>$($tr.name) [$status]</li>"
        }
        $detailedHtml += "</ul><hr/>"
    }

    # Close HTML
    $detailedHtml += "</body></html>"

    # ===== EXPORT FILES TO WORKING DIRECTORY =====
    $txtFile  = Join-Path $reportDir "DatabaseInventory.txt"
    $htmlFile = Join-Path $reportDir "DatabaseInventory.html"

    $detailedTxt | Out-File -FilePath $txtFile -Encoding UTF8
    $detailedHtml | Out-File -FilePath $htmlFile -Encoding UTF8

    # ===== SHOW SUMMARY TABLE IN CONSOLE =====
    Write-Host "`n===== SUMMARY TABLE =====" -ForegroundColor Cyan
    $summaryTable | Format-Table -AutoSize

    # ===== SHOW DETAILED LISTS IN CONSOLE PER DATABASE =====
    foreach ($dbSummary in $summaryTable) {
        $dbName = $dbSummary.Database
        $tables = $tablesByDb[$dbName]
        $fks    = $fksByDb[$dbName]
        $triggers = $triggersByDb[$dbName]
        $truncateInfo = $truncateInfoByDb[$dbName]

        Write-Host "`nDatabase: $dbName" -ForegroundColor Yellow
        Write-Host "Tables ($($dbSummary.Tables) total, $($dbSummary.TotalRows) rows):"
        foreach ($t in $tables) { Write-Host " - $($t.TableName) : $($t.TotalRows) rows" }
        Write-Host "Empty Tables: $($truncateInfo.Empty.Count)"
        Write-Host "Non-Empty Tables: $($truncateInfo.NotEmpty.Count)"

        Write-Host "Foreign Keys ($($dbSummary.ForeignKeys)):"
        foreach ($fk in $fks) { Write-Host " - $($fk.FKName) (Table: $($fk.TableName))" }
        if ($dbSummary.FKErrors -gt 0) { Write-Host "FK Errors: $($dbSummary.FKErrors)" }

        Write-Host "Triggers (Enabled: $($dbSummary.TriggersEnabled), Disabled: $($dbSummary.TriggersDisabled)):"
        foreach ($tr in $triggers) { 
            $status = if ($tr.is_disabled -eq 0) { "ENABLED" } else { "DISABLED" }
            Write-Host " - $($tr.name) [$status]" 
        }
        if ($dbSummary.TriggerErrors -gt 0) { Write-Host "Trigger Errors: $($dbSummary.TriggerErrors)" }

        Write-Host "---------------------------------------------------"
    }

    # ===== EXPORT CONFIRMATION =====
    Write-Host "`nInventory export complete!" -ForegroundColor Green
    Write-Host "TXT Report : $txtFile"
    Write-Host "HTML Report: $htmlFile"
}




 if ($inputs -eq "6") {

    Write-Host "`n===== SQL Script Execution =====" -ForegroundColor Cyan

    # Ensure server instance exists
    if (-not $serverInstance) {
        Write-Host "ERROR: SQL Server instance was not defined earlier." -ForegroundColor Red
        return
    }

    # Ensure databases were selected
    if (-not $databases -or $databases.Count -eq 0) {
        Write-Host "ERROR: No databases were selected earlier." -ForegroundColor Red
        return
    }

    # ---------------------- LOOP UNTIL GOOD SQL FILE -------------------------
    while ($true) {
        Write-Host "===== SQL Script Execution ====="
        $SqlScriptPath = Read-Host "Enter full SQL script path (.sql) or type 0 to exit"

        if ($SqlScriptPath -eq "0") {
            Write-Host "Exiting SQL script execution..."
            return
        }

        if ([string]::IsNullOrWhiteSpace($SqlScriptPath)) {
            Write-Host "ERROR: No path entered. Try again." -ForegroundColor Red
            continue
        }

        if (-not (Test-Path -Path $SqlScriptPath -PathType Leaf)) {
            if (Test-Path -Path $SqlScriptPath -PathType Container) {
                Write-Host "ERROR: You entered a directory, not a file." -ForegroundColor Red
            }
            else {
                Write-Host "ERROR: File does NOT exist." -ForegroundColor Red
            }
            continue
        }

        $item = Get-Item $SqlScriptPath
        if ($item.PSIsContainer -or $item.Extension -ne ".sql") {
            Write-Host "ERROR: Path must be a .sql file." -ForegroundColor Red
            continue
        }

        Write-Host "Valid SQL script selected: $SqlScriptPath" -ForegroundColor Green
        break
    }
    # -------------------------------------------------------------------------

    # ---------------------- DATABASE SELECTION -------------------------
    Write-Host "`nAvailable Databases:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $databases.Count; $i++) {
        Write-Host "[$($i+1)] $($databases[$i])"
    }

    Write-Host "`nSelect one or more database numbers separated by SPACE."
    Write-Host "Or type * for ALL databases (default *)."
    Write-Host "Or type 0 to exit."

    while ($true) {
        $selection = Read-Host "Database selection"

        if ($selection -eq "0") { return }

        if ([string]::IsNullOrWhiteSpace($selection) -or $selection -eq "*") {
            $SelectedDBs = $databases
            break
        }

        $entries = $selection -split '\s+'
        $valid = $true
        $SelectedDBs = @()

        foreach ($e in $entries) {
            if ($e -notmatch '^\d+$') {
                Write-Host "Invalid number: $e" -ForegroundColor Red
                $valid = $false
                break
            }
            $num = [int]$e
            if ($num -lt 1 -or $num -gt $databases.Count) {
                Write-Host "Invalid selection number: $num" -ForegroundColor Red
                $valid = $false
                break
            }
            $SelectedDBs += $databases[$num - 1]
        }

        if ($valid) { break }
    }
    # -------------------------------------------------------------------------

    Write-Host "`nExecuting SQL script on selected databases..." -ForegroundColor Cyan

    # Initialize summary array
    $VerificationSummary = @()

    # ---------------------- EXECUTE SQL PER DATABASE -------------------------
    foreach ($db in $SelectedDBs) {

        Write-Host " "

        # Choose authentication
        if ($choice -eq "1") {
            $connString = "Server=$serverInstance;Database=$db;User Id=$username;Password=$plainPassword;"
        }
        elseif ($choice -eq "2") {
            $connString = "Server=$serverInstance;Database=$db;Trusted_Connection=True;"
        }
        else {
            Write-Host "Invalid choice. Exiting."
            exit
        }

        # Create a log file per database
        $LogFile = "$workingDir\SQLExecution_$db_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
        Add-Content -Path $LogFile -Value "===== SQL Script Execution Log ====="
        Add-Content -Path $LogFile -Value "Date: $(Get-Date)"
        Add-Content -Path $LogFile -Value "Server Instance: $serverInstance"
        Add-Content -Path $LogFile -Value "Database: $db"
        Add-Content -Path $LogFile -Value "SQL Script: $SqlScriptPath`n"

        Write-Host "`nRunning SQL script on '$db'..." -ForegroundColor Cyan

        try {
            Invoke-Sqlcmd -ConnectionString $connString -InputFile $SqlScriptPath -ErrorAction Stop
            Add-Content -Path $LogFile -Value "SUCCESS: SQL script executed successfully.`n"
            Write-Host "SUCCESS on $db" -ForegroundColor Green

            $SqlExecutionStatus = "OK"
            $SqlExecutionComment = "Executed successfully"
        }
        catch {
            Add-Content -Path $LogFile -Value "FAILED: $($_.Exception.Message)`n"
            Write-Host "FAILED on $db" -ForegroundColor Red
            Write-Host $_.Exception.Message -ForegroundColor DarkRed

            $SqlExecutionStatus = "FAILED"
            $SqlExecutionComment = $_.Exception.Message
        }

        Write-Host "Log file for $db : $LogFile" -ForegroundColor Yellow

        # --- Check errors in the log ---
        $logLines = Get-Content -Path $LogFile
        $hasErrors = $false
        foreach ($line in $logLines) {
            if ($line -match "FAILED" -or $line -match "Could not find file") {
                Write-Host $line -ForegroundColor Red
                $hasErrors = $true
            }
        }

        # Summary entry
        $VerificationSummary += [PSCustomObject]@{
            "Validation Type" = "SQL Execution: $db"
            "Status"          = $SqlExecutionStatus
            "Comments"        = $SqlExecutionComment
        }
    }

    # ---------------------- PRINT SUMMARY -------------------------
    Write-Host "`n===== SQL Execution Summary =====" -ForegroundColor Cyan
    $VerificationSummary | Format-Table -AutoSize

    Write-Host "`nAll executions completed."
}




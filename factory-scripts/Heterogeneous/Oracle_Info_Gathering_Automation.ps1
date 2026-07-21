#!/usr/bin/pwsh
CLS
Write-Host  " Checking ressources..."


   Write-Host ""
 


function Exit-Code {
    Write-Host "-Ending Execution"
    exit
}

function Create-Folder([string]$path) {
    if (Test-Path $path) {
        Write-Host "-Folder '$path' exists..."
    } else {
        New-Item -ItemType Directory -Path $path | Out-Null
        Write-Host "-$path folder created..."
    }
}

# Resolve script root reliably
$Folder = $PSScriptRoot
if (-not $Folder) { $Folder = Split-Path -Parent $MyInvocation.MyCommand.Path }

# --- Detect sqlplus (Oracle SQL*Plus) ---


function Get-SqlPlusPath {
    <#
    .SYNOPSIS
        Vérifie si sqlplus est installé et retourne son chemin complet.
        Fonction compatible Windows, Linux et macOS.
    .OUTPUTS
        [string] Chemin complet vers sqlplus, ou $null si non trouvé
    #>

    $sqlplusPath = $null

$IsWindowsOS = ($env:OS -eq 'Windows_NT')



    if ($IsWindowsOS) {
 	Write-Host " The System OS is Windows"
        # Vérifie via Get-Command
	 Write-Host " execute Get-Command sqlplus.exe ..."
	 
        $cmd = Get-Command sqlplus.exe -ErrorAction SilentlyContinue
        if ($cmd) { $sqlplusPath = $cmd.Source }

        # Vérifie via where.exe si non trouvé
        if (-not $sqlplusPath) {
            try {
                $whereResult = & where.exe sqlplus 2>$null
                if ($whereResult) { $sqlplusPath = $whereResult[0] }
            } catch { }
        }
    } else {
        # Linux/macOS
        try {
            $whichResult = & which sqlplus 2>$null
            if ($whichResult) { $sqlplusPath = $whichResult.Trim() }
        } catch { }

        # Vérifie chemins classiques si non trouvé
        if (-not $sqlplusPath) {
            $commonPaths = @("/usr/bin/sqlplus","/usr/local/bin/sqlplus","/opt/oracle/product/21c/dbhome_1/bin/sqlplus")
            foreach ($p in $commonPaths) {
                if (Test-Path $p) { $sqlplusPath = $p; break }
            }
        }
    }

    return $sqlplusPath
}

Write-Host "                                                                                       " -BackgroundColor DarkMagenta
Write-Host "       Welcome to Factory - Oracle_Info_Gathering_Automation                                " -ForegroundColor White -BackgroundColor DarkMagenta
Write-Host "                  (OSS DB Migration factory)                                            " -BackgroundColor DarkMagenta
Write-Host "                                                                                       " -BackgroundColor DarkMagenta
Write-Host ""

$sqlplusPath = Get-SqlPlusPath
if ($sqlplusPath) {
Write-Host "Oracle client (sqlplus) found at: $sqlplusPath . Continuing..." -ForegroundColor Green
} else {
            Write-Host "Oracle client (sqlplus) not found. Please install or add to PATH, then re-run." -BackgroundColor Red
		Write-Host  " PATH ..."
		$env:Path
 		   

        Exit-Code
}


Write-Host ""




Write-Host "Please select the assessment operation to perform" -ForegroundColor Green
Write-Host "===================================================================="
Write-Host "1. Perform Oracle server Information gathering"
Write-Host "2. Exit"

$validInputs = "1","2"
do {
    $inputresponse = Read-Host -Prompt "Enter value"
    if (-not $validInputs.Contains($inputresponse)) { Write-Host "Please select the choice between 1 - 2" }
} until ($validInputs.Contains($inputresponse))

if ($inputresponse -eq "2") { Exit-Code }


# =========================================================
# FONCTIONS UTILITAIRES
# =========================================================
function Exit-Fatal($Message) {
    Write-Host "ERROR - $Message" -ForegroundColor Red
    exit 1
}

function Ask-File {
    param (
        [string]$Prompt,
        [string]$Default
    )

    while ($true) {
        $input = Read-Host "$Prompt [$Default]"

        if ([string]::IsNullOrWhiteSpace($input)) {
            $input = $Default
        }

        if (Test-Path $input -PathType Leaf) {
            return (Resolve-Path $input).Path
        }

        Write-Host "ERROR: File does not exist: $input" -ForegroundColor Red
    }
}



function Ask-Folder {
    param (
        [string]$Prompt,
        [string]$Default
    )

    while ($true) {
        $input = Read-Host "$Prompt [$Default]"
        if ([string]::IsNullOrWhiteSpace($input)) {
            $input = $Default
        }

        if (Test-Path $input -PathType Container) {
            return (Resolve-Path $input).Path
        }

        Write-Host "Directory does not exist: $input" -ForegroundColor Yellow
        $create = Read-Host "Do you want to create it? (y/n)"

        if ($create -match '^[Yy]$') {
            try {
                New-Item -ItemType Directory -Path $input -Force | Out-Null
                return (Resolve-Path $input).Path
            } catch {
                Write-Host "ERROR: Failed to create directory: $input" -ForegroundColor Red
            }
        }
    }
}


function Test-SqlPlus {
    if (Get-Command sqlplus -ErrorAction SilentlyContinue) { return $true }
    try { if ($IsWindowsOS) { if (& where.exe sqlplus 2>$null) { return $true } } else { if (& which sqlplus 2>$null) { return $true } } } catch {}
    return $false
}

 

function New-OracleWrapperScript {
    param($SqlFile,$ResultFile)

    $tmp = [System.IO.Path]::GetTempFileName() + ".sql"

@"
whenever sqlerror exit 1
set echo off
set feedback off
set heading on
set pagesize 500
set linesize 500
set trimout on
set trimspool on
spool $ResultFile
@$SqlFile
spool off
exit
"@ | Out-File -Encoding utf8 $tmp

    return $tmp
}

 function New-SqlPlusWrapper {
    param(
        [string]$SqlFile,
        [string]$ResultFile
    )

    $tmp = [System.IO.Path]::GetTempFileName() + ".sql"

@"
whenever sqlerror exit sql.sqlcode
set echo off
set feedback off
set heading off
set pagesize 0
set trimout on
set trimspool on
set termout off
spool $ResultFile
@$SqlFile
spool off
exit
"@ | Out-File -Encoding ascii $tmp

    return $tmp
}

function Write-ExecLog {
    param(
        [string]$LogFile,
        [string]$Message,
        [string]$Level = "INFO"
    )

    if (-not $LogFile) { return }

    "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) [$Level] $Message" |
        Out-File -Append -Encoding utf8 -FilePath $LogFile
}


function Invoke-Oracle {
    param(
        [string]$SqlPlusPath,
        [string]$EZConnect,
        [string]$SqlFile,
        [string]$ResultFile,
        [string]$LogFile
    )

    $wrapper = New-SqlPlusWrapper $SqlFile $ResultFile

    & $SqlPlusPath -L -S $EZConnect "@$wrapper"
    $exitCode = $LASTEXITCODE

    Remove-Item $wrapper -Force -ErrorAction SilentlyContinue

    $oraErrors = @()

    if (Test-Path $ResultFile) {
        $oraErrors = Select-String `
            -Path $ResultFile `
            -Pattern 'ORA-\d+|SP2-\d+|TNS-\d+'
    }

   # === Affichage écran ===
if ($oraErrors -and $oraErrors.Count -gt 0) {

    Write-Host "=========== ORACLE ERRORS ===========" -ForegroundColor Red

    foreach ($err in $oraErrors) {

        # Cas où $err est un MatchInfo (Select-String)
        if ($err.PSObject.Properties.Match('Line')) {
            Write-Host $err.Line -ForegroundColor Red
            Write-ExecLog $LogFile $err.Line "ERROR"
        }
        else {
            # Cas fallback (string simple)
            Write-Host $err -ForegroundColor Red
            Write-ExecLog $LogFile $err "ERROR"
        }
    }

}


    # === Retour fonction ===
    if ($oraErrors) {
        return @{
            Code  = 1
            Error = $oraErrors[0].Line
        }
    }

    if ($exitCode -ne 0) {
        return @{
            Code  = 1
            Error = "SQL*Plus failed (exit code $exitCode)"
        }
    }

    return @{ Code = 0 }
}
# =========================================================
# PRECHECK SQLPLUS
# =========================================================
if (-not (Test-SqlPlus)) { Exit-Fatal "sqlplus not found in PATH" }

# =========================================================
# DEFAULT PATHS
# =========================================================
$BaseDir = $PSScriptRoot

$DefaultSQL    = Join-Path $BaseDir "ora_db_gather.sql"
$DefaultLogDir = Join-Path $BaseDir "LOG"
$DefaultResDir = Join-Path $BaseDir "RESULT"
$DefaultCSV    = Join-Path $BaseDir "Factory_Oracle_Server_Input_file.csv"
# =========================================================
# ASK FILES AND FOLDERS
# =========================================================
$SqlScript = Ask-File "Enter full path of SQL file" $DefaultSQL
$LogDir    = Ask-Folder "Enter full LOG directory path" $DefaultLogDir
$OutputDir = Ask-Folder "Enter full RESULT directory path" $DefaultResDir
$CsvFile   = Ask-File "Enter full path of CSV file" $DefaultCSV

# =========================================================
# LOAD CSV AND FILTER APPROVED
# =========================================================
try {
    $AllRows = Import-Csv $CsvFile

    $requiredCols = @("Host_Name","UserName","Service_Name","Approval_Status")
    $missingCols = $requiredCols | Where-Object { -not ($AllRows | Get-Member -Name $_) }
    if ($missingCols.Count -gt 0) { Exit-Fatal "CSV missing required columns: $($missingCols -join ', ')" }

    $Rows = $AllRows | Where-Object {
        $_.Approval_Status -and ($_.Approval_Status.Trim().ToUpper() -eq "YES") -and $_.Service_Name
    }
} catch {
    Exit-Fatal "Error reading CSV: $($_.Exception.Message)"
}

if ($Rows.Count -eq 0) { Exit-Fatal "No approved entries found in CSV" }

# =========================================================
# MAIN LOOP
# =========================================================
$Summary = @()
$DateStamp = Get-Date -Format "yyyyMMdd_HHmmss"

foreach ($row in $Rows) {
    $HostName = $row.Host_Name.Trim()
    $Port     = if ($row.Port) { $row.Port.Trim() } else { "1521" }
    $Service  = $row.Service_Name.Trim()
    $User     = $row.UserName.Trim()
    $Pass     = $row.UserPassword.Trim()
    $Environment     = $row.Environment.Trim()

    








Write-Host ""
Write-Host "-----------------------------------------------------"
Write-Host "Looping the line [$HostName $Service $Port $User] ...." -ForegroundColor Blue
 



$HostName = $row.Host_Name
$Port     = if ($row.Port) { $row.Port.Trim() } else { "1521" }
$Service  = $row.Service_Name
$User     = $row.UserName
$Pass     = $row.UserPassword

# ---------------------------------------------------
# Mandatory fields validation
# ---------------------------------------------------
$missingFields = @()

if ([string]::IsNullOrWhiteSpace($HostName)) { $missingFields += "Host_Name" }
if ([string]::IsNullOrWhiteSpace($User))     { $missingFields += "UserName" }
if ([string]::IsNullOrWhiteSpace($Service))  { $missingFields += "Service_Name" }

if ($missingFields.Count -gt 0) {

    Write-Host "`nERROR: Missing mandatory field(s) in CSV file." -ForegroundColor Red
    Write-Host "The following field(s) are required:" -ForegroundColor Red
    Write-Host " - $($missingFields -join ', ')" -ForegroundColor Red

    Write-Host "`nPlease do one of the following before continuing:" -ForegroundColor Yellow
    Write-Host "1. Fill in the missing value(s) in the CSV file" -ForegroundColor Yellow
    Write-Host "2. Remove the invalid line from the CSV file" -ForegroundColor Yellow
    Write-Host "`nThen re-run the script." -ForegroundColor Yellow

    Exit 1
}

# Trim values after validation
$HostName = $HostName.Trim()
$Service  = $Service.Trim()
$User     = $User.Trim()
$Pass     = if ($Pass) { $Pass.Trim() } else { $null }





if (-not $Pass) {
    do {
        Write-Host ""
        $securePass = Read-Host -Prompt "Enter password for $User@$HostName/$Service (0 to exit)" -AsSecureString

        # Conversion correcte SecureString -> String
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePass)
        $PassPlain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

        # Quitter si 0
        if ($PassPlain -eq "0") {
            Write-Host "Exiting..."
            exit 0
        }

        if ([string]::IsNullOrWhiteSpace($PassPlain)) {
            Write-Host "Password cannot be empty. Please try again." -ForegroundColor Yellow
            $Pass = $null
        } else {
            $Pass = $PassPlain
        }

    } until ($Pass)
}


$TNSALIAS = "(DESCRIPTION = (ADDRESS = (PROTOCOL = TCP)(HOST = $HostName)(PORT = $Port ))(CONNECT_DATA = (SERVICE_NAME = $Service))(CONNECT_TIMEOUT = 10) (TRANSPORT_CONNECT_TIMEOUT = 10))"

    



    $EZConnect = "$User/$Pass@$HostName`:$Port/$Service"

Write-Host ""
 

Write-Host "Testing connection on the database for $HostName/$Service ..."  -ForegroundColor  Yellow
 


function Test-OracleConnection {
    param(
        [string]$SqlPlusPath,
        [string]$EZConnect,
        [int]$TimeoutSec = 10
    )

    $TestSQL = "whenever sqlerror exit 1;`nselect 'OK' from dual;`nexit;"

    try {
        if ($IsWindowsOS) {
            $output = cmd /c "echo $TestSQL | `"$SqlPlusPath`" -S $EZConnect" 2>&1
        } else {
            $output = echo $TestSQL | & $SqlPlusPath -S $EZConnect 2>&1
        }

        $lines = $output -split "`n" | ForEach-Object { $_.Trim() }

        if ($lines -match "ORA-|TNS-|SP2-") {
            Write-Host "ERROR - Connection failed" -ForegroundColor Red
            $lines | Where-Object { $_ -match "ORA-|TNS-|SP2-" } |
                Select-Object -First 1 |
                ForEach-Object { Write-Host $_ -ForegroundColor Red }
            return $false
        }

        Write-Host "SUCCESS - Connection OK" -ForegroundColor Green
        Write-Host ""
       

        return $true
    }
    catch {
        Write-Host "ERROR - $_" -ForegroundColor Red
        return $false
    }
}



$connectionOK = Test-OracleConnection `
    -SqlPlusPath $sqlplusPath `
    -EZConnect $EZConnect `
    -TimeoutSec 10

if (-not $connectionOK) {
    Write-Host "Skipping SQL execution for $HostName/$Service due to connection failure." -ForegroundColor Yellow

    $Summary += [pscustomobject]@{
        Host       = $HostName
        Service    = $Service
        Status     = "CONNECTION_FAILED"
        LogFile    = "N/A"
        ResultFile = "N/A"
    }

    continue   # ← passe à la ligne CSV suivante
}

$safe = ($HostName + "_" + $Service + "_" + $DateStamp) -replace "[^\w]", "_"

$ResultFile = Join-Path $OutputDir "result_${safe}_${Environment}.txt"
$LogFile    = Join-Path $LogDir    "exec_${safe}.log"

# Exécuter le script SQL
 Write-Host "Executing the Sql Script. Please wait...." -ForegroundColor Yellow
 
$res = Invoke-Oracle `
    -SqlPlusPath $sqlplusPath `
    -EZConnect $EZConnect `
    -SqlFile $SqlScript `
    -ResultFile $ResultFile `
    -LogFile $LogFile 
     

# Capturer uniquement la première ligne d'erreur ORA-, TNS- ou SP2-
$oraErr = ($res.Output -split "`r?`n" |
           ForEach-Object { $_.Trim() } |
           Where-Object { $_ -match '^(ORA-\d+|SP2-|TNS-)' } |
           Select-Object -First 1)

if ($res.Code -eq 0 -and -not $oraErr) {

    Write-Host "$HostName / $Service : SUCCESS" -ForegroundColor Green
    Write-Host "   Log file   : $LogFile"
    Write-Host "   Result file: $ResultFile"

    Write-ExecLog $LogFile "SUCCESS"
    $Summary += [pscustomobject]@{
        Host       = $HostName
        Service    = $Service
        Status     = "SUCCESS"
        LogFile    = $LogFile
        ResultFile = $ResultFile
    }

} else {

    $shortErr = if ($oraErr) {
        $oraErr
    } elseif ($res.Code -ne 0) {
        "sqlplus exited with errors   "
    } else {
        "SQL execution failed (see log)"
    }

    Write-Host "$HostName / $Service : ERROR - $shortErr" -ForegroundColor Red
    Write-Host "   Log file   : $LogFile"
    Write-Host "   Result file: $ResultFile"

    Write-ExecLog $LogFile $shortErr "ERROR"
    $Summary += [pscustomobject]@{
        Host       = $HostName
        Service    = $Service
        Status     = "FAILED"
        LogFile    = $LogFile
        ResultFile = $ResultFile
    }
}
}



# =========================================================
# FINAL SUMMARY
# =========================================================
$SummaryFile = Join-Path $LogDir ("summary_$DateStamp.txt")

Write-Host ""
Write-Host "================ EXECUTION SUMMARY ================" -ForegroundColor Cyan
Write-Host ""

# Largeur dynamique des colonnes (alignement propre)
$hostWidth    = ($Summary.Host    | Measure-Object -Maximum Length).Maximum
$serviceWidth = ($Summary.Service | Measure-Object -Maximum Length).Maximum
$statusWidth  = 8

# En-tête
Write-Host (
    "{0,-$hostWidth}  {1,-$serviceWidth}  {2,-$statusWidth}  {3}" -f `
    "Host","Service","Status","LogFile"
)

# Séparateur
Write-Host (
    "{0}  {1}  {2}  {3}" -f `
    ("-" * $hostWidth),
    ("-" * $serviceWidth),
    ("-" * $statusWidth),
    "-------"
)

# Lignes
foreach ($row in $Summary) {

    # Colonnes Host + Service
    Write-Host (
        "{0,-$hostWidth}  {1,-$serviceWidth}  " -f `
        $row.Host,
        $row.Service
    ) -NoNewline

    # Colonne Status (COULEUR UNIQUEMENT ICI)
    switch ($row.Status) {
        "FAILED"  { Write-Host ("{0,-$statusWidth}" -f $row.Status) -ForegroundColor Red   -NoNewline }
        "SUCCESS" { Write-Host ("{0,-$statusWidth}" -f $row.Status) -ForegroundColor Green -NoNewline }
        default   { Write-Host ("{0,-$statusWidth}" -f $row.Status) -NoNewline }
    }

    # Colonne LogFile
    Write-Host ("  {0}" -f $row.LogFile)
}

# =========================================================
# EXPORT SUMMARY FILE (TEXTE - SANS COULEUR)
# =========================================================
$Summary | ForEach-Object {
    "Host       : $($_.Host)"
    "Service    : $($_.Service)"
    "Status     : $($_.Status)"
    "Log File   : $($_.LogFile)"
    "Result File: $($_.ResultFile)"
    "----------------------------------------"
} | Out-File -FilePath $SummaryFile -Encoding utf8

Write-Host ""
Write-Host "Full summary saved to: $SummaryFile" -ForegroundColor Cyan

# Exit avec code 1 si au moins une erreur
if ($Summary.Status -contains "FAILED") { exit 1 }
exit 0
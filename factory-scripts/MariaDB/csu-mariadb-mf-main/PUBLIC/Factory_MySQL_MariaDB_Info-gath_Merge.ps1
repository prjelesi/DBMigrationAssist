#---------------------------------------------------------------------------------------------------------------------------*
#  Purpose        : Script to fetch Information from MySQL or MariaDB.
#  Schedule       : Ad-Hoc / On-Demand
#  Date           : 15-June-2023
#  Author         : Rackimuthu Kandaswamy ,Arun,Mukesh
#  Version        : 1.2
#   
#  INPUT          : Server List and other parameters in CSV file
#  VARIABLE       : NONE
#  PARENT         : NONE
#  CHILD          : NONE
#---------------------------------------------------------------------------------------------------------------------------*
#---------------------------------------------------------------------------------------------------------------------------*
#
#  IMPORTANT NOTE : The script has to be run on Non-Mission-Critical systems ONLY and not on any production server...
#
#---------------------------------------------------------------------------------------------------------------------------*
#---------------------------------------------------------------------------------------------------------------------------*
# Usage:
# Powershell.exe -File .\Factory-MySQL_Server_Automation_V1.1.ps1
#
# Change Log 31st July 2023 Sireesha Error Handling and MySQL validation 

CLS

function exitCode {
    Write-Host "-Ending Execution"
    exit
}

function createFolder([string]$newFolder) {
    if (Test-Path $newFolder) {
        Write-Host "-Folder '$newFolder' Exist..."
    } else {
        New-Item $newFolder -ItemType Directory
        Write-Host "-$newFolder folder created..."
    }
}

#---------------------------------------------------------PROGRAM BEGINS HERE----------------------------------------------------------

write-host "                                                                                       " -BackgroundColor DarkMagenta
Write-Host "       Welcome to Factory - MySQL/MariaDB Info Gathering Automation                          " -ForegroundColor white -BackgroundColor DarkMagenta
write-host "                  (OSS DB Migration factory)                                           " -BackgroundColor DarkMagenta
write-host "                                                                                       " -BackgroundColor DarkMagenta
Write-Host " "

$folder = $PSScriptRoot
$today_date = Get-Date -Format "MM_dd_yyyy_HH_mm"
Start-Transcript -path "$folder\Logs\Factory-Info_Gathering_Automation_Transcript_$today_date.txt" -Append

# Prompt for operation selection
Write-Host "Please select the assessment operation to perform" -ForegroundColor Green
Write-Host "===================================================================="
Write-Host "1. Info-gathering script for MySQL"
Write-Host "2. Info-gathering script for MariaDB"
Write-Host "3. Exit"

$operation = Read-Host "Enter your choice (1/2/3)"

switch ($operation) {
    1 {
        $dbType = "MySQL"
        $command = "mysql"
    }
    2 {
        $dbType = "MariaDB"
        $command = "mariadb"
    }
    3 {
        exitCode
    }
    default {
        Write-Host "Invalid selection. Exiting..." -ForegroundColor Red
        exitCode
    }
}

# Check if the selected database command exists
$commandPath = where.exe $command
if (-not $commandPath) {
    Write-Host "$dbType is not installed or its path is not in the environment variables. Please install $dbType and rerun the script." -BackgroundColor Red
    exitCode
} else {
    Write-Host "$dbType exists. Continuing execution..." -ForegroundColor Green
}

$Global:project_name = ""
createFolder $folder\Downloads\
createFolder $folder\Output\

Write-Host "Input Section " -ForegroundColor Green
$Global:project_name = Read-Host "Enter your project name"

Write-Host "Checking for MySQL path" -ForegroundColor white
#$MySQL_validdation_file_path=$Folder+"\MySQL_validation.bat"
$MySQL_Log_File="$Folder\Output\MySQL_validation.log"
$errMySQL_Log_File="$Folder\Output\MySQL_validation.err"
#$MySQL_OP = Start-Process -FilePath $MySQL_validdation_file_path -ArgumentList "$MySQL_Log_File"-Wait -WindowStyle Hidden
$mysqlCommand="mysql --version"
Invoke-Expression "$mysqlCommand 2>&1 | Out-File -FilePath $MySQL_Log_File"
$stat = $LASTEXITCODE

If( $stat -ne 0)
    {
       # seems to have failed
       $errorMessage = $Error[0].Exception.Message
       $errorMessage | Out-File -FilePath $errMySQL_Log_File -Append
       $error_m=Get-content -path $errMySQL_Log_File | out-string
       continue
    }

$content_check=Get-content -path $MySQL_Log_File 
if (Test-Path $MySQL_Log_File) {
    
    $content_check1=$content_check.ToLower()
    if (($content_check1 -like "*error*") -or ($content_check1 -like "*'mysql' is not recognized as an internal or external command*")){ 
    #Write-host $path_check -ForegroundColor red
    Write-host $content_check -ForegroundColor red
    write-host "Either MySQL client tool is not installed on the server or MySQL Path is not set in environment variable" -ForegroundColor red 
    write-host ""
    write-host "Please check and re-run automation script"
    exitcode
    }
    else
    {
        Write-host "MySQL validated successfully" -ForegroundColor Green
    }
    

    }
    Write-host ""

    $validInputs_Yes_No = "y", "n"
     
    Write-Host    "Please press Y to continue MySQL Info-Gathering .Press N to terminate the execution " -ForegroundColor Green
    Write-Host "======================================================================================="
    
    do {
    $response = read-host "Please provide your inputs"
    if(-not $validInputs_Yes_No.Contains($response)){write-host "Please Enter a valid input (Y or N )"}
    
    }until ($validInputs_Yes_No.Contains($response.ToLower()))

    if($response -eq "n"){exitcode}  

# Read the input config CSV and validate
$inputfile = "$Folder\Factory_${dbType}_Server_Input_file.csv"
Write-Host "Input file is $inputfile." -ForegroundColor Green
Write-Host "======================================================================================="

if (-not (Test-Path -Path $inputfile -PathType Leaf)) {
    Write-Host "Unable to read the input file [$inputfile]. Check file & its permission..." -ForegroundColor Red
    exitCode
}

try {
    $sqllist_Read_CSV = Import-Csv -Path $inputfile
    $Approved_Rows = $sqllist_Read_CSV | Where-Object { $_.Approval_Status.toupper() -eq "YES" }
    $ConfigList = $Approved_Rows | Group-Object -Property 'Host_Name' | ForEach-Object { $_.Group | Select-Object -First 1 }

    if ($ConfigList.count -eq 0) {
        Write-Host "None of the hosts are approved to proceed. Terminating the execution" -ForegroundColor Red
        exitCode
    }

    $ColumnList = $ConfigList | Get-Member -MemberType NoteProperty | % { "$($_.Name)" }
    if (($ColumnList.Contains("Host_Name")) -and
        ($ColumnList.Contains("User_ID")) -and
        ($ColumnList.Contains("Password")) -and
        ($ColumnList.Contains("DB_Name")) -and
        ($ColumnList.Contains("Tenant")) -and
        ($ColumnList.Contains("Subscription_ID")) -and
        ($ColumnList.Contains("SSL_Mode"))) {
        Write-Host "Input validation is done successfully"
    } else {
        Write-Host "There are mismatches in the Input columns. Kindly check and retrigger the automation" -ForegroundColor Red
        exitCode
    }
} catch {
    Write-Host "Error reading the input file: $_" -ForegroundColor Red
    exitCode
}

Write-Host "======================================================================================="
Write-Host "Here are the List of the Hosts the automation will proceed based on the user selection -" -ForegroundColor Green
Write-Host "======================================================================================="

Write-Host ($ConfigList | select Host_Name | Format-Table | Out-String)

$validInputs_Yes_No = "y", "n"
Write-Host "Please enter Y if you wish to continue, otherwise please press N to exit" -ForegroundColor Green
Write-Host "======================================================================================="

do {
    $response1 = read-host "Please provide your inputs"
    if (-not $validInputs_Yes_No.Contains($response1)) {
        write-host "Please Enter a valid input (Y or N)"
    }
} until ($validInputs_Yes_No.Contains($response1.ToLower()))

if ($response1 -eq "n") { exitCode }

$i = 0
#$Output_data=@("Source_Instance","Target_Instance","Log_Shipping_Status","Comments")
$Output_data = @()

foreach ($row_Content in $ConfigList) {
    $Host_Name = $row_Content.'Host_Name'
    if ([string]::IsNullOrWhitespace($Host_Name)) {
        Write-Host "'Host_Name' is not valid in the Server_List worksheet. Kindly check and retrigger the automation" -ForegroundColor Red
        Continue
    }
    $User_ID = $row_Content.'User_ID'
    if ([string]::IsNullOrWhitespace($User_ID)) {
        Write-Host "'User_ID' is not valid in the Server_List worksheet. Kindly check and retrigger the automation" -ForegroundColor Red
        Continue
    }
    $Password = $row_Content.'Password'
    if ([string]::IsNullOrWhitespace($Password)) {
        $credentials = Get-Credential -User Name $User_ID -Message "Please provide valid credentials for $Host_Name"
        $Password = $credentials.GetNetworkCredential().Password
        if ([string]::IsNullOrWhitespace($Password)) {
            Write-Host "'Password' is not valid in the Server_List worksheet. Kindly check and retrigger the automation" -ForegroundColor Red
            Continue
        }
    }
    $DB_Name = $row_Content.'DB_Name'
    if ([string]::IsNullOrWhitespace($DB_Name)) {
        Write-Host "'DB_Name' is not valid in the Server_List worksheet. Kindly check and retrigger the automation" -ForegroundColor Red
        Continue
    }

    $Port = $row_Content.'Port'
    if ([string]::IsNullOrWhitespace($Port)) {
        $Port = 3306
    }

    $SSL = $row_Content.'SSL_Mode'
    if ([string]::IsNullOrWhitespace($SSL)) {
        Write-Host "'SSL_Mode' is not valid in the Server_List worksheet. Kindly check and retrigger the automation" -ForegroundColor Red
        Continue
    }
	
	#$Trigger_File_Path=$Folder+"\Trigger_Mysql.bat"
    $date = Get-Date -Format "dd-HH-mm"
    $Log_Name= $Host_Name.replace(".", "_")
    $Log_Name=$Log_Name+"_"+$date
    $DbGather_Path="$Folder\\MySQL_Templates\\dbgather.sql"
    $Log_File=$Folder+"\Output\"+$Global:project_name+"_"+$Host_name+"_"+$DB_Name+".log"


    ##Execute MySQL command 
    Write-Host "=======================================================================================" 
    Write-host "Inititating Info-Gathering for " $Host_Name -ForegroundColor Green
    

    $sourceFilePath="$Folder\mysql.cnf"
    $destinationFilePath="$Folder\config.cnf"
    $searchPattern="NEWPASS"
    Copy-Item -Path $sourceFilePath -Destination $destinationFilePath
    $content = Get-Content -Path $destinationFilePath -Raw
    $newContent = $content -replace $searchPattern, $password
    Set-Content -Path $destinationFilePath -Value $newContent

    if(($command -eq "MySQL") -or ($command -eq "mysql"))
    {
        if($auth_type -eq 'entraid')
        {
            $mysqlCommand="$command --defaults-extra-file=$destinationFilePath -u $User_ID -h $Host_Name -P $Port -D $DB_Name --enable-cleartext-plugin --ssl-mode=$SSL -e ""source $DbGather_path"""

        }
        else {
            $mysqlCommand="$command --defaults-extra-file=$destinationFilePath -u $User_ID -h $Host_Name -P $Port -D $DB_Name --ssl-mode=$SSL -e ""source $DbGather_path"""
        }
    }
    else
    {
        $mysqlCommand = "$command --defaults-extra-file=$destinationFilePath -u $User_ID -h $Host_Name -P $Port -D $DB_Name --ssl=$SSL -e ""source $DbGather_path"""
    }
    #Write-host $mysqlCommand

    Invoke-Expression "$mysqlCommand 2>&1 | Out-File -FilePath $Log_File"
    $stat = $LASTEXITCODE
	  Write-Output "Last operation status: $stat"
    If( $stat -ne 0)
    {
       # seems to have failed
       $errorMessage = $Error[0].Exception.Message
       #$errorMessage | Out-File -FilePath $errpsql_Log_File -Append
       #$error_m=Get-content -path $errpsql_Log_File | out-string
       #continue
    }

    if (Test-Path $Log_File) {
        
        $size = Get-Content -Path $Log_File -Raw
        if ($size -match "VERSION") {
            Write-Host "Information Gathered is stored at $Log_File"
            Write-Host "Info-Gathering Successfully completed for $Host_Name" -ForegroundColor Green
            $Output_data += New-Object psobject -Property @{Host_Name=$Host_Name;Status="SUCCESS";LOG_File_Location=$Log_File;Error_msg="NA"}
        } else {
            $error_msg = Get-Content -Path $Log_File | Out-String
            $Output_data += New-Object psobject -Property @{Host_Name=$Host_Name;Status="FAILED";LOG_File_Location=$Log_File;Error_Msg=$error_msg}
            Write-Host "*** Failed to gather information for $Host_Name" -ForegroundColor Red
            Write-Host $error_msg -ForegroundColor Red
        }
    } else {
        $Output_data += New-Object psobject -Property @{Host_Name=$Host_Name;Status="FAILED";LOG_File_Location="NA";Error_Msg="Log file not created"}
    }
}


 

Write-Host "" 
Write-Host "======================================================================================="  
Write-Host "Below is The final status of $dbType Script Execution "  -ForegroundColor Green  
Write-Host "======================================================================================="

Write-Host ($Output_data | select Host_Name,Status,Error_Msg | Format-Table -AutoSize -wrap | Out-String)  

if ($Output_data -ne " ") {
    $Output_data | select Host_Name,Status,LOG_File_Location,Error_Msg | Export-Csv "$folder\Output\Output.csv" -NoTypeInformation    
}

Stop-Transcript
exitCode
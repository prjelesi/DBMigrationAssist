#---------------------------------------------------------------------------------------------------------------------------*
#  Purpose        : Script to fetch Information from MySQL.
#  Schedule       : Ad-Hoc / On-Demand
#  Date           : 15-June-2023
#  Author         : Rackimuthu Kandaswamy , Sireesha , VenkannaBabu , Saby
#  Version        : 1.1
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
# Powershell.exe -File ./Factory-MariaDB_Server_Automation_V1.1.ps1
#
#change Log 31st July 2023 Sireesha Error Handling and MySQL validation 

#$folder = the working dicectory , where the scripts are saved

CLS

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

#---------------------------------------------------------PROGRAM BEGINS HERE----------------------------------------------------------



write-host "                                                                                       " -BackgroundColor DarkMagenta
Write-Host "       Welcome to Factory - MariaDB_Info_Gathering_Automation                                " -ForegroundColor white -BackgroundColor DarkMagenta
write-host "                  (OSS DB Migration factory)                                           " -BackgroundColor DarkMagenta
write-host "                                                                                       " -BackgroundColor DarkMagenta
Write-Host " "

$folder = $PSScriptRoot
$MariaDBpath = which mysql
$today_date=Get-Date -Format "MM_dd_yyyy_HH_mm"
Start-Transcript -path  $folder/Logs/Factory-MariaDB_Info_Gathering_Automation_Transcript_$today_date.txt -Append

if ($MariaDBpath -like "*/mysql*") {
	Write-Host "MySQL exists. Continuing execution..." -ForegroundColor Green
}
else {
	Write-Host "MySQL does not exists. Please install MySQL and re-execute the script" -BackgroundColor Red
	break
}

$Global:project_name = ""

Write-Host "======================================================================================= "
createFolder $folder/Downloads/
createFolder $folder/Output/

Write-Host ""
Write-Host "======================================================================================= "

Write-Host "Input Section "   -ForegroundColor Green

$Global:project_name = Read-Host "Enter your project name"

Write-Host "Checking for MySQL path" -ForegroundColor white
#$MySQL_validdation_file_path=$Folder+"/MySQL_validation.bat"
$MySQL_Log_File="$Folder/Output/MySQL_validation.log"
$errMySQL_Log_File="$Folder/Output/MySQL_validation.err"
#$MySQL_OP = Start-Process -FilePath $MySQL_validdation_file_path -ArgumentList "$MySQL_Log_File"-Wait -WindowStyle Hidden
$mysqlCommand="mysql --version"
Invoke-Expression "$mysqlCommand 2>&1 | Out-File -FilePath $MySQL_Log_File"
$stat = $LASTEXITCODE

If( $stat -ne 0)
    {
       # seems to have failed
       Write-Host "Failed to validate MySQL location" -ForegroundColor RED
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
$inputfile = "$Folder/Factory_MariaDB_Server_Input_file.csv"
Write-Host "Input file is $inputfile." -ForegroundColor Green
Write-Host "======================================================================================="


if (-not(Test-Path -Path $inputfile -PathType Leaf)) {
     try {    
         Write-Host "======================================================================================="  
         Write-Host "Unable to read the input file [$inputfile]. Check file & its permission...  "  -ForegroundColor Red  
         Write-Host "======================================================================================="  
         Write-Host "Please see the error below & execution has been stopped          "  
         throw $_.Exception.Message                      
     }
     catch {
         throw $_.Exception.Message
     }
 }
else
{
     try {
         $sqllist_Read_CSV = Import-Csv -Path $inputfile #-WorksheetName Server_List
         $Approved_Rows = $sqllist_Read_CSV | Where-Object { $_.Approval_Status.toupper() -eq "YES" }

         $ConfigList = $Approved_Rows | Group-Object -Property 'Host_Name' | ForEach-Object {
                $_.Group | Select-Object -First 1
	}
         

         $Rowcount=0

          foreach($row in $ConfigList){
             $Hostname = $row.'Host_Name'
              $Rowcount=$Rowcount+1
          }
      
    }
     catch {
         Write-Host "=================================================================================="  
         Write-Host "The file [$inputfile] does not have the woksheet named Server_List  "  -ForegroundColor Red  
         Write-Host "=================================================================================="  
         Write-Host "Please see the error below &execution has been stopped          "  
         throw $_.Exception.Message
     }

if($ConfigList.count -eq 0){

write-host "None of the hosts are approved to proceed . Terminating the execution" -ForegroundColor Red

exitcode

}

     $ColumnList=$ConfigList | Get-Member -MemberType NoteProperty | %{"$($_.Name)"}
     if (($ColumnList.Contains("Host_Name")) -and
        ($ColumnList.Contains("User_ID")) -and
        ($ColumnList.Contains("Password")) -and
        ($ColumnList.Contains("DB_Name")) -and
        ($ColumnList.Contains("Tenant")) -and
        ($ColumnList.Contains("Subscription_ID")) -and
        ($ColumnList.Contains("SSL_Mode"))){

        Write-Host "Input validation is done successfully " 
        }
     else {Write-Host "There are missmatches in the Input columns. Kindly check and retrigger the automation "  -ForegroundColor Red 
           exitCode}
  }


##Input CSV validation is done



Write-Host "=======================================================================================" 
    Write-Host "Here are the List of the Hosts the automation will proceed based on the user selection -" -ForegroundColor Green
    Write-Host "=======================================================================================" 

$db_Selection_Display=@()

 Write-Host ($ConfigList | select Host_Name | Format-Table | Out-String)
  
  Write-Host "=======================================================================================" 
    Write-Host "Please enter Y if you wish to continue , otherwise please press N to exit" -ForegroundColor Green
    Write-Host "=======================================================================================" 
    do {
    $response1 = read-host "Please provide your inputs"
    if(-not $validInputs_Yes_No.Contains($response1)){write-host "Please Enter a valid input (Y or N )"}
    
    }until ($validInputs_Yes_No.Contains($response1.ToLower()))

 if($response1 -eq "n"){exitcode} 

$i = 0
#$Output_data=@("Source_Instance","Target_Instance","Log_Shipping_Status","Comments")
$Output_data =@()

foreach ($row_Content in $ConfigList) {

        $Host_Name=$row_Content.'Host_Name'
        if ([string]::IsNullOrWhitespace($Host_Name)){
            Write-Host "'Host_Name' is not valid in the Server_List worksheet. Kindly check and retrigger the automation  "  -ForegroundColor Red 
            Continue
        }
        $User_ID=$row_Content.'User_ID'
        if ([string]::IsNullOrWhitespace($User_ID)){
            Write-Host "'User_ID' is not valid in the Server_List worksheet. Kindly check and retrigger the automation  "  -ForegroundColor Red 
            Continue
        }
        $auth_type = $row_Content.'auth_type'
        $Password=$row_Content.'Password'

        if ([string]::IsNullOrWhitespace($Password)){
             #check for EntraId user
            if ($auth_type -eq 'entraid'){
                #check if az cli is installed
                if( [bool](Get-Command -Name 'az' -ErrorAction SilentlyContinue)){
                    $Password = $(az account get-access-token --resource-type oss-rdbms --output tsv --query accessToken)
                }
                else{
                    Write-Host "Azure Entra Authenticaton required but no az cli detected. Kindly check az cli installation and retrigger the automation  "  -ForegroundColor Red 
                }
            }
            else {

                $credentials = Get-Credential -UserName $User_ID -Message "Please provide valid credentials for $Host_Name"
                $Password = $credentials.GetNetworkCredential().Password
                if ([string]::IsNullOrWhitespace($Password)){
                    Write-Host "'Password' is not valid in the Server_List worksheet. Kindly check and retrigger the automation  "  -ForegroundColor Red 
                    Continue
                }
            }            
        }

        $DB_Name=$row_Content.'DB_Name'
        if ([string]::IsNullOrWhitespace($DB_Name)){
            Write-Host "'DB_Name' is not valid in the Server_List worksheet. Kindly check and retrigger the automation  "  -ForegroundColor Red 
            Continue
        }

        $Port=$row_Content.'Port'
		#if(($Port -eq "") -or ($Port -eq $null) -or ($Port -eq " ")) {
		if ([string]::IsNullOrWhitespace($Port)){
			$Port = 3306
			#Write-Host "'Port' is not valid in the Server_List worksheet. Kindly check and retrigger the automation  "  -ForegroundColor Red 
			Continue
		}

        $SSL=$row_Content.'SSL_Mode'
        if ([string]::IsNullOrWhitespace($DB_Name)){
            Write-Host "'SSL_Mode' is not valid in the Server_List worksheet. Kindly check and retrigger the automation  "  -ForegroundColor Red 
            Continue
        }

    #$Trigger_File_Path=$Folder+"/Trigger_Mysql.bat"
    $date = Get-Date -Format "dd-HH-mm"
    $Log_Name= $Host_Name.replace(".", "_")
    $Log_Name=$Log_Name+"_"+$date
    $DbGather_Path="$Folder/MySQL_Templates/dbgather.sql"
    $Log_File=$Folder+"/Output/"+$Global:project_name+"_"+$Host_name+"_"+$DB_Name+".log"


    ##Execute MySQL command 
    Write-Host "=======================================================================================" 
    Write-host "Inititating Info-Gathering for " $Host_Name -ForegroundColor Green
    #$Mysql_OP = Start-Process -FilePath $Trigger_File_Path -ArgumentList "$User_ID", "$Host_Name", "$Password" , "$DB_Name" , "$DbGather_Path" , "$Log_File" -Wait -WindowStyle Hidden
    #$escapedDBCommand = "`"-D $DB_Name --ssl-mode=$SSL`""
    #$mysqlCommand = "mysql -h %$Host_Name% --ssl-mode=%$SSL% -u %$User_ID% %%x < %%x_%dt_ts%.sql"
    #$mysqlCommand="mysql -u $User_ID -h $Host_Name -P $Port -p $Password -D $DB_Name --ssl-mode=$SSL < $DbGather_path > $Log_File"
     
    $Config_File="$Folder/config.cnf"
    if (($null -ne $Config_File) -AND (Test-Path -Path $Config_File)) {
        chmod 700 $Config_File
    }
    echo [client] > $Config_File
    echo password=$password >> $Config_File
    chmod 400 $Config_File
    if($auth_type -eq 'entraid')
    {
        $mysqlCommand="mysql --defaults-extra-file=$Config_File -u $User_ID -h $Host_Name -P $Port -D $DB_Name --enable-cleartext-plugin --ssl-mode=$SSL -e ""source $DbGather_path"""

    }
    else {

              $mysqlCommand="mysql --defaults-extra-file=$Config_File -u $User_ID -h $Host_Name -P $Port -D $DB_Name --ssl-mode=$SSL -e ""source $DbGather_path"""
    }


    #Write-host $mysqlCommand
    Invoke-Expression "$mysqlCommand 2>&1 | Out-File -FilePath $Log_File"
    $stat = $LASTEXITCODE
   # Write-Output "Last operation status: $stat"
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
    if($size -match "VERSION") {
        Write-host "Information Gathered is stored at "$Log_File
        Write-host "Info-Gathering Successfully  completed for " $Host_Name -ForegroundColor Green
        $Output_data += New-Object psobject -Property @{Host_Name=$Host_Name;Status="SUCCESS";LOG_File_Location=$Log_File;Error_msg="NA"}

    }
    else{
        $error_msg=Get-content -path $Log_File | Out-String
        $Output_data += New-Object psobject -Property @{Host_Name=$Host_Name;Status="FAILED";LOG_File_Location=$Log_File;Error_Msg=$error_msg}
        Write-Host "*** Loop if Failed to" -ForegroundColor RED
        Write-Host "Failed to run MySQL server" -ForegroundColor RED
        write-host $error_msg -ForegroundColor red    	
    }
}
else {
    $Output_data += New-Object psobject -Property @{Host_Name=$Host_Name;Status="FAILED";LOG_File_Location="NA";Error_Msg="NA"}
}


      
$i = $i + 1
 #End Read config For each
 
 }


Write-Host "" 
Write-Host "======================================================================================="  
Write-Host "Below is The final status of MariaDB Script Execution "  -ForegroundColor Green  
Write-Host "======================================================================================="

#Write-Host ($Output_data | select Host_Name,Status,LOG_File_Location,Error_Msg| Format-Table -AutoSize -wrap| Out-String)  
Write-Host ($Output_data | select Host_Name,Status,Error_Msg| Format-Table -AutoSize -wrap| Out-String)  

if ($Output_data -ne "")
{
    $Output_data | select Host_Name,Status,LOG_File_Location,Error_Msg | Export-Csv "$Folder/Output/Output.csv" -NoTypeInformation    
}
if (($null -ne $Config_File) -AND (Test-Path -Path $Config_File)) { chmod 700 $Config_File;Remove-Item $Config_File}
Stop-Transcript
exitcode

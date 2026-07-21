#---------------------------------------------------------------------------------------------------------------------------*
#  Purpose        : Script for Creating Flexible server sync to Azure MySQL Single Server
#  Schedule       : Ad-Hoc / On-Demand
#  Date           : 05-DEC-2023
#  Author         : Madan Agrawal
#  Version        : 2.1
#   
#  INPUT          : NONE
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
# Powershell.exe -File .\Factory-MySQL_Azure_SingleServer_to_Flexible.ps1
#
<#
    Change Log
    ----------
•	Customer consent to install Azure CLI.
•   MySQL client is required.
•   Added Parallel execution for multiple migration
•   Added Offline/online migration  
•   Added Multiple subscription support  
•   support for data encryption using CMK enabled 
        
#>
Set-ExecutionPolicy Bypass -Scope currentuser
Clear-Host

#---------------------------------------------------------PROGRAM BEGINS HERE----------------------------------------------------------

write-host "                                                                            " -BackgroundColor DarkMagenta
Write-Host "     Welcome to Factory - MySQL_Azure_SingleServer_to_Flexible_Automation       " -ForegroundColor white -BackgroundColor DarkMagenta
write-host "                     (OSS DB Migration Factory)                             " -BackgroundColor DarkMagenta
write-host "                                                                            " -BackgroundColor DarkMagenta
Write-Host " "
$PSScriptRoot="C:\Users\v-madagrawal\MySQL-Info-Gather-Adhoc"
$folder = $PSScriptRoot
$Outdate = '{0}' -f ([system.string]::format('{0:yyyyMMddHHmmss}',(Get-Date)))
$Validation=@()
$Output_data =@()
$Progress_data =@()


Write-Host "`n======================================================================================="
Start-Transcript -path  $folder\Logs\Factory_MySQL_Azure_SingleServer_to_Flexible_Automation_Transcript_$Outdate.txt -Append
Write-Host "`n======================================================================================="


function Config_MySQL($Az_import,$Log_File,$Subscription,$uid,$DB_Name,$SSL,$pass,$cert,$port,$SingleServerInfo,$FlexServerInfo,$destinationFilePath, $sslEnforcement,$Mig_mode,$progressfile,$CMKParameter)
{
  
   #Setting Subscription
    az account set -s $Subscription

$hostname1=$Az_import.split("""")[3]
$hostname=$hostname1+".mysql.database.azure.com"
$RG=$Az_import.split("""")[5]
$mysqlFlexi=$Az_import.split("""")[7]
$Single_uid=$uid+"@"+$hostname1
if ($null -ne $CMKParameter)
{
$Az_import=$Az_import+$CMKParameter+" --only-show-errors"
}
else
{
$Az_import=$Az_import +" --only-show-errors"
}

        Invoke-Expression "$Az_import"
        $stat = $LASTEXITCODE 
         If($Mig_mode -match "ONLINE")
         {
         $Content=Get-Content $Log_File | select-object -skip 7
         }
         else
         {
         $Content=Get-Content $Log_File 
         }
         Write-output $Content | write-host -ForegroundColor yellow

if($stat -ne 0)
{
        $errorMessage = $Error[0].Exception.Message
        Write-host $errorMessage -ForegroundColor Red
        Write-host "`n----------End Time::$(Get-Date -format 's')-----------`n"
          $Output_data += New-Object psobject -Property @{Host_Name=$hostname;Status="Failed";Error_msg=$errorMessage}
           #$Output_data | select-object Host_Name, Status, Error_msg | Export-CSV -NoTypeInformation -Path $progressfile
}   
else
{
   az mysql flexible-server show --ids "/subscriptions/$Subscription/resourceGroups/$RG/providers/Microsoft.DBforMySQL/flexibleServers/$mysqlFlexi" > $FlexServerInfo
   
   Write-host "`n Refer ""$FlexServerInfo"" to get the property of provisioned mysql flexible host [$mysqlFlexi]`n"
 
    If($Mig_mode -match "ONLINE")
   {

   $commandFlexi="""call mysql.az_show_binlog_file_and_pos_for_mysql_import;"""

   $connectionFlexi="mysql --defaults-extra-file=$destinationFilePath -h $mysqlFlexi.mysql.database.azure.com -u $uid -D $DB_Name --ssl-mode=$SSL -e "
 
   $execFlexi=$connectionFlexi+$commandFlexi


  "`n**********************************************`n" >> $Log_File  
  "MYSQL>call mysql.az_show_binlog_file_and_pos_for_mysql_import" >> $Log_File  

   $FlexConnFailed=0
   $tries = 0

    while ($tries -lt 4) 
    {
       
              
              Invoke-Expression "$execFlexi 2>&1 >> $Log_File"
                $stat = $LASTEXITCODE
                If( $stat -ne 0)
                {
                 Write-host "Host [$mysqlFlexi] is not ready to accept connection.retrying connection after 15s..." -ForegroundColor Yellow
                 start-sleep 15
                 $errorMessage = $Error[0].Exception.Message  
                 $FlexConnFailed = 1
                 $tries++
                 If ($tries -eq 3){
                 $Output_data += New-Object psobject -Property @{Host_Name=$hostname;Status="Failed";Error_msg=$errorMessage}
                  #$Output_data | select-object Host_Name, Status, Error_msg | Export-CSV -NoTypeInformation -Path $progressfile
                  "Not able to connect to provisioned MySql flexi server [$mysqlFlexi]. Kindly check - $errorMessage"  >> $Log_File
    
                 }
                 
                 
                }
                else
                {
               $MyData = Get-Content $Log_File -Tail 2
                  #$MyData |Out-File -FilePath $Log_File -Append
               Write-host "`nconnected successfully to host [$mysqlFlexi]" -ForegroundColor Green
               $FlexConnFailed=0
               $tries=4  
                }
                     
       
         }
       

#if($FlexConnFailed -ne 1)
if($FlexConnFailed -ne 1)
{
Write-host "Executed ""call mysql.az_show_binlog_file_and_pos_for_mysql_import""" -ForegroundColor Blue

$MyData=-split $MyData[1]
$binlog=$MyData[0]
$binLogFile=$binlog.substring($binlog.IndexOf("/")+1)
$Position= $MyData[1]

Write-host "`nFile:"$binLogFile
Write-host "Position:"$Position

 "`n**********************************************`n" >> $Log_File  
 
If ($sslEnforcement -eq "Enabled")
  {
  $command="""call mysql.az_replication_change_master('$hostname', '$Single_uid', '$pass', $port, '$binLogFile', $Position, '$cert')"""
  Write-host "`nExecuting... " -ForegroundColor Blue
  Write-host "call mysql.az_replication_change_master('$hostname', '$Single_uid', '*****', $port, '$binLogFile', $Position, '*****')" -ForegroundColor Blue
  "MYSQL>call mysql.az_replication_change_master('$hostname', '$Single_uid', '*****', $port, '$binLogFile', $Position, '*****')" >> $Log_File 
  }
  else
  {
    $command="""call mysql.az_replication_change_master('$hostname', '$Single_uid', '$pass', $port, '$binLogFile', $Position, '')"""
    Write-host "`nExecuting... " -ForegroundColor Blue
    Write-host "call mysql.az_replication_change_master('$hostname', '$Single_uid', '*****', $port, '$binLogFile', $Position, '')" -ForegroundColor Blue
     "MYSQL>call mysql.az_replication_change_master('$hostname', '$Single_uid', '*****', $port, '$binLogFile', $Position, '')" >> $Log_File 
  }

   $execFlexi=$connectionFlexi+$command
    #"`nExecuting [$execFlexi] on [$mysqlFlexi]`n" >> $Log_File 
    Invoke-Expression "$execFlexi 2>&1 >> $Log_File"
    $MyData = Get-Content $Log_File -Tail 2
     
$MyDataH=$MyData[0].split("`t")
$MyDataD=$MyData[1].split("`t")

If ($MyDataH[0] -contains "exception")
{
Write-host "`nFailed to execute ""Call mysql.az_replication_change_master""`n" -ForegroundColor Red
write-host "Error Message:"$MyDataD[2] -ForegroundColor Red
$Output_data += New-Object psobject -Property @{Host_Name=$hostname;Status="Failed";Error_msg="$MyDataD[2]"}
 #$Output_data | select-object Host_Name, Status, Error_msg | Export-CSV -NoTypeInformation -Path $progressfile
continue
}
else
{
Write-host $MyDataD[0] -ForegroundColor Green
}

Write-host "`nExecuting ""call mysql.az_replication_start""`n" -ForegroundColor Blue
 "`n**********************************************`n" >> $Log_File
"MYSQL>call mysql.az_replication_start" >> $Log_File 

$command="""call mysql.az_replication_start"""

$execFlexi=$connectionFlexi+$command
 #"`nExecuting [$execFlexi] on [$mysqlFlexi]`n" >> $Log_File 
Invoke-Expression "$execFlexi 2>&1 >> $Log_File"
$MyData = Get-Content $Log_File -Tail 2
$MyDataH=$MyData[0].split("`t")
$MyDataD=$MyData[1].split("`t")

If ($MyDataH[0] -contains "exception")
{
Write-host "`nFailed to execute ""call mysql.az_replication_start""`n" -ForegroundColor Red
write-host "Error Message:"$MyDataD[2] -ForegroundColor Red
$Output_data += New-Object psobject -Property @{Host_Name=$hostname;Status="Failed";Error_msg="$MyDataD[2]"}
 #$Output_data | select-object Host_Name, Status, Error_msg | Export-CSV -NoTypeInformation -Path $progressfile
    
}
else
{
Write-host $MyDataD[0] -ForegroundColor Green

}}
}
$Output_data += New-Object psobject -Property @{Host_Name=$hostname;Status="SUCCESS";Error_msg="NA"}


}
 "$Output_data">> $Log_File 
 if (($null -ne $destinationFilePath) -AND (Test-Path -Path $destinationFilePath)) { Remove-Item $destinationFilePath} 
}


 
 function IsFileNotAccessible( [String] $FullFileName )
{
  [Boolean] $IsNotAccessible = $true

  while ($IsNotAccessible)
  {
  try
  {
    Rename-Item $FullFileName $FullFileName -ErrorVariable LockError -ErrorAction Stop
   
    $IsNotAccessible = $false
  }
  catch
  {

    $IsNotAccessible = $true
      write-host "The process cannot access the file $progressfile because it is being used by another process.`nRetrying after 10s..." -ForegroundColor Red
      start-sleep 10
  }
  }
  
    #return $IsNotAccessible
}

function exitCode
{
    Write-Host "-Ending Execution"
    Stop-Transcript
    exit
}
 
function createFolder([string]$newFolder) 
{
    if(Test-Path $newFolder)
    {
  Write-Host "-Folder'$newFolder' Exist..."
    }
    else
    {
      $CreateD=New-Item $newFolder -ItemType Directory
    Write-Host "-$newFolder folder created..."
    }
}


Remove-Job *
createFolder $folder\Downloads\
createFolder $folder\Logs\
createFolder $folder\Output\
createFolder $folder\Output\Single\
createFolder $folder\Output\Flexi\


Write-Host "======================================================================================="

#Check for mysql-Client
Write-Host "Checking for MySQL path" -ForegroundColor white

$MySQL_Log_File="$folder\Output\MySQL_validation.log"
$errMySQL_Log_File="$folder\Output\MySQL_validation.err"
$mysqlCommand="mysql --version"
Invoke-Expression "$mysqlCommand 2>&1 | Out-File -FilePath $MySQL_Log_File"
$stat = $LASTEXITCODE

If( $stat -ne 0)
    {
       # if failed
       Write-Host "Failed to validate MySQL location" -ForegroundColor RED
       $errorMessage = $Error[0].Exception.Message
       $errorMessage | Out-File -FilePath $errMySQL_Log_File -Append
       $errorMessage=Get-content -path $errMySQL_Log_File | out-string
       $OutputMySQL = New-Object psobject -Property @{Validation_Type="Check MySQL Client";Status="Failed";Comments=$errorMessage}
       continue
    }

$content_check=Get-content -path $MySQL_Log_File 
if (Test-Path $MySQL_Log_File) {
    
    $content_check1=$content_check.ToLower()
    if (($content_check1 -like "*error*") -or ($content_check1 -like "*'mysql' is not recognized as an internal or external command*")){ 
    Write-host $content_check -ForegroundColor red
    write-host "Either MySQL client tool is not installed on the server or MySQL Path is not set in environment variable" -ForegroundColor red 
    write-host ""
    write-host "Please check and re-run automation script"
    exitcode
    }
    else
    {
        Write-host "MySQL validated successfully" -ForegroundColor Green
          $OutputMySQL = New-Object psobject -Property @{Validation_Type="Check MySQL Client";Status="SUCCESS";Comments="MySQL validated successfully"}
    }
    

    }


    
#Unblock-File $folder/Validation_Scripts/Check_PowerShell_Version.ps1
#Unblock-File $folder/Validation_Scripts/azurecli.ps1
     
# Check PowerShell version

$Validation+=$OutputMySQL
$Validation+=& "$folder/Validation_Scripts/Check_PowerShell_Version.ps1"
$Validation+=& "$folder/Validation_Scripts/azurecli.ps1"

Write-Host "======================================================================================="  
Write-Host "Below are the Validation Results"  -ForegroundColor Green  
Write-Host "======================================================================================="  
Write-Host ($Validation | Select-Object Validation_Type,Status,Comments | Format-Table | Out-String)

If($Validation.Status.Contains("FAILED"))
{
 Write-Host "There are errors during validation . Terminating the execution ."  -ForegroundColor Red
 exitcode  
}

# Read the input config CSV and validate
$Configfile = $folder+"\Factory_MySQL_Server_Input_file.csv" 
Write-Host "`n`nInput config file is $Configfile." -ForegroundColor Green
#Write-Host "===================================================================="  


if (-not(Test-Path -Path $Configfile -PathType Leaf)) {
    try {    
         Write-Host "======================================================================================="  
         Write-Host "Unable to read the Configfile file [$Configfile]. Check file & its permission...  "  -BackgroundColor Red
         Write-Host "======================================================================================="  
         Write-Host "Please see the error below Execution has been stopped          "  
         throw $_.Exception.Message                      
    }
    catch {
         throw $_.Exception.Message
    }
 }
else
{
     try {
         $ConfigList = Import-Csv -Path $Configfile

         }

         catch {
         Write-Host "=================================================================================="  
         Write-Host "Unable to read file [$Configfile] or this file does not exist"  -BackgroundColor Red 
         Write-Host "=================================================================================="  
         exitcode
        }

}
 $ColumnList=$ConfigList | Get-Member -MemberType NoteProperty | ForEach-Object{"$($_.Name)"}
     if (($ColumnList.Contains("Tenant")) -and
        ($ColumnList.Contains("Subscription_ID"))){

        Write-Host "Config file validation is done successfully " 
        }
     else {Write-Host "There are mismatches in the config CSV column . Kindly check and retrigger the automation "  -BackgroundColor Red
           exitCode}


 
if(($ConfigList.'Tenant' |Get-Unique).count -eq 1)
{
$tenant=$ConfigList.'Tenant' |Get-Unique


#AZ login to corresponsing Tenant and subscription

$loginoutput = az login --tenant $tenant
}

if (!$loginoutput) 
{
    Write-Error "Error connecting to Tenant: $tenant and Subscription: $Subscription"
    exitcode
}

else
{
    $Serverdata=@()
    $Outfiledata=@()    

    #AZ Connect to provided subscription#>
   # az account set --subscription $Subscription
    }
    

 
#Validating exported mysql single server input file
$inputfile = $Configfile
$progressfile=$folder+"\output\Progress_tracker_$Outdate.csv" 


if (-not(Test-Path -Path $inputfile -PathType Leaf)) {
    try {    
         Write-Host "======================================================================================="  
         Write-Host "Unable to read the MySQL Input file [$inputfile]. Check file & its permission...  "  -BackgroundColor Red
         Write-Host "======================================================================================="  
         Write-Host "Please see the error below Execution has been stopped          "  
         throw $_.Exception.Message                      
    }
    catch {
         throw $_.Exception.Message
    }
 }
else
{
     try {
       
        $ServerList    = Import-Csv -Path $inputfile  
        $Approved_Rows = $ServerList | Where-Object { $_.Approval_Status.toupper() -eq "YES" }
        $Not_Approved  = $ServerList | Where-Object { $_.Approval_Status.toupper() -eq "NO" }
        
            if($null -ne $Not_Approved)
            { 
             $loop=0
             #$Not_Approved| ForEach-Object {[PSCustomObject]$_}  | Export-CSV -NoTypeInformation -Path $progressfile
             $Not_Approved_count=$Not_Approved.Host_Name.split(',').count
        
            while ($Not_Approved_count -gt $loop)  
            {
            $Output_data += New-Object psobject -Property @{Host_Name=$Not_Approved.Host_Name.split(',')[$loop];Status="Not Approved";Error_msg="NA"}
            $loop++
            }
            $Output_data | select-object Host_Name, Status, Error_msg | Export-CSV -NoTypeInformation -Path $progressfile
            }

         $ServerList=$Approved_Rows
            }

         catch {
         Write-Host "=================================================================================="  
         Write-Host "Unable to read file [$inputfile] or it does not have the valid Server_List"  -BackgroundColor Red 
         Write-Host "=================================================================================="  
         exitcode
        }

}
$Progress_data=$Output_data
Write-Host "`nMySQL single server input file is $inputfile." -ForegroundColor Green

 if ($null -eq $ServerList) 
{
    write-host "None of the hosts are approved to proceed . Terminating the execution..." -ForegroundColor Red

exitcode
}
else
{



 $ColumnList=$ServerList | Get-Member -MemberType NoteProperty | ForEach-Object{"$($_.Name)"}
     if (($ColumnList.Contains("Host_Name")) -and
        ($ColumnList.Contains("Resource_Group")) -and
        ($ColumnList.Contains("User_ID")) -and
        ($ColumnList.Contains("Password")) -and
        ($ColumnList.Contains("DB_Name")) -and
        ($ColumnList.Contains("Port")) -and
        ($ColumnList.Contains("Destination")) -and
        ($ColumnList.Contains("Tier")) -and
        ($ColumnList.Contains("sku-name")) -and
        ($ColumnList.Contains("storage-size")) -and
        ($ColumnList.Contains("admin-user")) -and
        ($ColumnList.Contains("admin-password")) -and
        ($ColumnList.Contains("SSL_Mode")) -and
         ($ColumnList.Contains("SSL_Cert")) -and
        ($ColumnList.Contains("Migration_mode")) -and
        ($ColumnList.Contains("Approval_Status"))){

        Write-Host "Input mysql servers list validation completed successfully " 
        }
     else {
     Write-Host "There are missmatches in the column names. Kindly check and retrigger the automation "  -ForegroundColor Red 
           exitCode
           }

  Write-host "`n`nBelow list of MySQL servers are approved for flexible server migration"

  $ServerList | Select-Object Host_name, Resource_Group, Destination, Approval_Status, Migration_mode  | Format-Table

  $validInputs = "Y", "y", "N", "n"
  do {
         $response = read-host "Enter 'Y' to continue or 'N' to abort"
         if(-not $validInputs.Contains($response)){write-host "Invalid Entry...try again"}
     } until ($validInputs.Contains($response))


    if($response.tolower().Contains("n"))
    {
        exitcode
    }
    else
    {
        Write-Host "Proceeding for Flexible server Provisioning and Migration..." -ForegroundColor Green
    }
}

	 
    $joblist=@()  
 
 
  foreach ($mysql in $ServerList)
  {

  $Subscription=$mysql.'Subscription_ID'
 #Setting Subscription
   az account set -s $Subscription

    $keyIdentifier=$null
   # $mysql =$ServerList[0]
		$hostname=$mysql.'Host_Name'
        $hostname1=$hostname.split('.')[0]
        $Log_File=$folder+"\Output\"+$hostname1+"_"+"$Outdate.log"  
     write-host "`n`n-----------------------------------------------------------------------------------------------------------------------------------------"
     write-host "Processing Source Single server [$hostname] on Subscription [$Subscription]              "
     write-host "-----------------------------------------------------------------------------------------------------------------------------------------"
     #select-object "$hostname1", "In Progress", "NA" | Export-CSV -NoTypeInformation -Path $progressfile -Append
  

		if ([string]::IsNullOrWhitespace($hostname)){
			Write-Host "'Host_Name' is not valid in the Factory-MySQL_Single_Server_Input_file.CSV worksheet. Kindly check and retrigger the automation  "  -ForegroundColor Red 
               $Output_data += New-Object psobject -Property @{Host_Name=$hostname;Status="Failed";Error_msg="Host_Name' is not valid"}
                #$Output_data | select-object Host_Name, Status, Error_msg | Export-CSV -NoTypeInformation -Path $progressfile
                Set-Content -Path $Log_File -Value "Server - $hostname `n`n`nError: 'Host_Name' is not valid in the Factory-MySQL_Single_Server_Input_file.CSV worksheet."
			Continue
		}
		
		$MysqlUID=$mysql.'User_ID'
		if ([string]::IsNullOrWhitespace($MysqlUID)){
			Write-Host "'User_ID' is not valid in the Factory-MySQL_Single_Server_Input_file.CSV worksheet. Kindly check and retrigger the automation  "  -ForegroundColor Red 
            $Output_data += New-Object psobject -Property @{Host_Name=$hostname;Status="Failed";Error_msg="'User_ID' is not valid"}
            #$Output_data | select-object Host_Name, Status, Error_msg | Export-CSV -NoTypeInformation -Path $progressfile
            Set-Content -Path $Log_File -Value "Server - $hostname `n`n`nError: 'User_ID' is not valid in the Factory-MySQL_Single_Server_Input_file.CSV worksheet."
			Continue
		}
	
		$MysqlPwd=$mysql.'Password'
		if ([string]::IsNullOrWhitespace($MysqlPwd)){
			Write-Host "'Password' is not valid in the Factory-MySQL_Single_Server_Input_file.CSV worksheet. Kindly check and retrigger the automation  "  -ForegroundColor Red 
            $Output_data += New-Object psobject -Property @{Host_Name=$hostname;Status="Failed";Error_msg="'Password' is not valid"}
             #$Output_data | select-object Host_Name, Status, Error_msg | Export-CSV -NoTypeInformation -Path $progressfile
            Set-Content -Path $Log_File -Value "Server - $hostname `n`n`nError: 'Password' is not valid in the Factory-MySQL_Single_Server_Input_file.CSV worksheet."
			Continue
		}
        $DB_Name=$mysql.'DB_Name'
        if ([string]::IsNullOrWhitespace($DB_Name)){
            Write-Host "'DB_Name' is not valid in the Factory-MySQL_Single_Server_Input_file.CSV worksheet. Kindly check and retrigger the automation  "  -ForegroundColor Red 
                  $Output_data += New-Object psobject -Property @{Host_Name=$hostname;Status="Failed";Error_msg="'DB_Name' is not valid"}
                   #$Output_data | select-object Host_Name, Status, Error_msg | Export-CSV -NoTypeInformation -Path $progressfile
                   Set-Content -Path $Log_File -Value "Server - $hostname `n`n`n Error: 'DB_Name' is not valid in the Factory-MySQL_Single_Server_Input_file.CSV worksheet."
            Continue
        }

	    $mysqlFlexi=$mysql.Destination.toLower()
		if ([string]::IsNullOrWhitespace($mysqlFlexi)){
			Write-Host "'Destination' is not valid in the Factory-MySQL_Single_Server_Input_file.CSV worksheet. Kindly check and retrigger the automation  "  -ForegroundColor Red
             $Output_data += New-Object psobject -Property @{Host_Name=$hostname;Status="Failed";Error_msg="'Destination' is not valid"}
              #$Output_data | select-object Host_Name, Status, Error_msg | Export-CSV -NoTypeInformation -Path $progressfile
              Set-Content -Path $Log_File -Value "Server - $hostname `n`n` Error: 'Destination' is not valid in the Factory-MySQL_Single_Server_Input_file.CSV worksheet." 
			Continue
		}

        $RG=$mysql.Resource_Group  
		if ([string]::IsNullOrWhitespace($RG)){
			Write-Host "'Resource Group' is not valid in the Factory-MySQL_Single_Server_Input_file.CSV worksheet. Kindly check and retrigger the automation  "  -ForegroundColor Red
            $Output_data += New-Object psobject -Property @{Host_Name=$hostname;Status="Failed";Error_msg="'Resource Group' is not valid"}  
             #$Output_data | select-object Host_Name, Status, Error_msg | Export-CSV -NoTypeInformation -Path $progressfile
            Set-Content -Path $Log_File -Value "Server - $hostname `n`n`n Error: 'Resource Group' is not valid in the Factory-MySQL_Single_Server_Input_file.CSV worksheet." 
			Continue
		}
        $Mig_mode=$mysql.Migration_mode.toUpper()
		if ([string]::IsNullOrWhitespace($Mig_mode) -or ($Mig_mode -notin ("ONLINE","OFFLINE")) ){
			Write-Host "'Migration_mode' is not valid in the Factory-MySQL_Single_Server_Input_file.CSV worksheet. Kindly check and retrigger the automation  "  -ForegroundColor Red
             $Output_data += New-Object psobject -Property @{Host_Name=$hostname;Status="Failed";Error_msg="'Migration_mode' is not valid"}
               #$Output_data | select-object Host_Name, Status, Error_msg | Export-CSV -NoTypeInformation -Path $progressfile
              Set-Content -Path $Log_File -Value "Server - $hostname `n`n` Error: 'Migration_mode' is not valid in the Factory-MySQL_Single_Server_Input_file.CSV worksheet." 
			Continue
		}
        $SSL=$mysql.'SSL_Mode'
        if ([string]::IsNullOrWhitespace($SSL)){
            Write-Host "'SSL_Mode' is not valid in the Factory-MySQL_Single_Server_Input_file.CSV worksheet. Kindly check and retrigger the automation  "  -ForegroundColor Red 
            $Output_data += New-Object psobject -Property @{Host_Name=$hostname;Status="Failed";Error_msg="'SSL_Mode' is not valid"}  
             #$Output_data | select-object Host_Name, Status, Error_msg | Export-CSV -NoTypeInformation -Path $progressfile
            Set-Content -Path $Log_File -Value "Server - $hostname `n`n`n Error: 'SSL_Mode' is not valid in the Factory-MySQL_Single_Server_Input_file.CSV worksheet." 
			Continue
        }

    $port=$mysql.Port
    

    if($port -eq ""){
        $port='3306'
        } 

     if($DB_Name -eq ""){
        $DB_Name="mysql"
        } 

    $SSL_cert=$mysql.SSL_Cert
    If($SSL_cert -eq "")
  {
  $cert=Get-Content $PSScriptRoot/Validation_Scripts/DigiCertGlobalRootG2.crt.pem -Raw
  }
  Else
  {
  $cert=Get-Content $SSL_cert -Raw
 
  }
                  
  $Az_import="az mysql flexible-server import create --data-source-type ""mysql_single"" --data-source ""$hostname1"" --resource-group ""$RG"" --name ""$mysqlFlexi"""

  $tier=$mysql.Tier
     
  if ($tier -ne "")     { $Az_import=$Az_import+" --tier "+"$tier"  } 
 
  $sku=$mysql."sku-name"

  if ($sku -ne "")     { $Az_import=$Az_import+" --sku-name "+"""$sku"""  } 

  $storage=$mysql."storage-size"

  if ($storage -ne "") { $Az_import=$Az_import+" --storage-size "+$storage } 
 
  $admin_user=$mysql."admin-user"
 
       if ($admin_user -eq "") 
        {
        $uid=$mysql.User_ID.split("@")[0]
        }
        else
        {
            $Az_import=$Az_import+" --admin-user "+$admin_user
            $uid=$admin_user
        } 
 
  $admin_pass=$mysql."admin-password"

 
       if ($admin_pass -eq "")
         {
         $pass=$mysql.Password
        
         }
     else
         {
         $Az_import=$Az_import+" --admin-password "+$admin_pass
         $pass=$admin_pass
         } 
 
  
  $SingleServerInfo="$PSScriptRoot\Output\Single\"+"$hostname"+"_$Outdate.json"
  $FlexServerInfo="$PSScriptRoot\Output\Flexi\$mysqlFlexi.mysql.database.azure.com_$Outdate.json"  
     # az mysql server show --ids "/subscriptions/$Subscription/resourceGroups/$RG/providers/Microsoft.DBforMySQL/servers/$hostname1" > $SingleServerInfo 
    
    #write-host "tier:" $ServerData[0].sku.tier
    #write-host "Compute Generation:" $ServerData[0].sku.family
    #write-host "vCore:" $ServerData[0].sku.capacity
    #write-host "storage:" $ServerData[0].storageProfile.storageMb
    #write-host "Location:" $ServerData[0].location
    #write-host "sslEnforcement:" $ServerData[0].sslEnforcement
    #write-host "-----------------------------------------------------------------------------------------------------------"
   
       if (($mysqlFlexi.length -gt 63) -or ($mysqlFlexi.length -lt 3) -or ($mysqlFlexi -match "[^a-z0-9-]"))
       {
       Write-host "`nError - The Flexible server name can contain only lowercase letters, numbers, and the hyphen (-) character. Minimum 3 characters and maximum 63"  -ForegroundColor Red
       Write-host "NOTE: The 'Destination' column in input CSV file shouldn't suffix with .mysql.database.azure.com.`n"  -ForegroundColor Red
       Set-Content -Path $Log_File -Value "Error - The Flexible server name can contain only lowercase letters, numbers, and the hyphen (-) character. Minimum 3 characters and maximum 63"
       $Output_data += New-Object psobject -Property @{Host_Name=$hostname;Status="Failed";Error_msg="The Flexible server name can contain only lowercase letters, numbers, and the hyphen (-) character. Minimum 3 characters and maximum 63"}  
      #$Output_data | select-object Host_Name, Status, Error_msg | Export-CSV -NoTypeInformation -Path $progressfile
       continue
       }
    
    If($Mig_mode -LIKE "ONLINE")
    {
    $sourceFilePath="$folder\mysql.cnf"
    $destinationFilePath="$folder\$hostname1.cnf"
    #$searchPattern="defaults-extra-file"
    $searchPattern="NEWPASS"
    Copy-Item -Path $sourceFilePath -Destination $destinationFilePath
    $content = Get-Content -Path $destinationFilePath -Raw
    $newContent = $content -replace $searchPattern, $MysqlPwd
    Set-Content -Path $destinationFilePath -Value $newContent

       
     $connectionSingle="mysql --defaults-extra-file=$destinationFilePath  -h $hostname -u $MysqlUID -D $DB_Name --ssl-mode=$SSL -e ""SHOW VARIABLES LIKE 'log_bin'"""
     "************************ $hostname ****************************** `n">> $Log_File
     "MYSQL>SHOW VARIABLES LIKE 'log_bin'" >> $Log_File
         Invoke-Expression "$connectionSingle 2>&1 >> $Log_File"
         $stat = $LASTEXITCODE
  
    If( $stat -ne 0)
    {
      
       $errorMessage = $Error[0].Exception.Message
        $Output_data += New-Object psobject -Property @{Host_Name=$hostname;Status="Failed";Error_msg="$errorMessage"}
       #$Output_data | select-object Host_Name, Status, Error_msg | Export-CSV -NoTypeInformation -Path $progressfile
        Write-host $errorMessage -ForegroundColor Red
     continue
    }

        
         $MyData = Get-Content $Log_File -Tail 2 
         "`n**********************************************`n" >> $Log_File  
            #$MyData| Out-File -FilePath $Log_File -Append
            
          $MyData=-split $MyData[1]
            
    If ($MyData -match "ERROR")
          {
                    Write-host "Not able to connect Source MYSQL [$hostname]." -ForegroundColor Red
                    Write-host $MyData -ForegroundColor Red
                    Write-host "`nPlease refer log file @ $Log_File`n" -ForegroundColor Red
                    #Set-Content -Path $SingleServerErr -Value $_.Exception.Message
                    $Output_data += New-Object psobject -Property @{Host_Name=$hostname;Status="Failed";Error_msg="$MyData"}
                     #$Output_data | select-object Host_Name, Status, Error_msg | Export-CSV -NoTypeInformation -Path $progressfile
                    #if (Test-Path $Log_File_temp) { Remove-Item $Log_File_temp} 
                    continue; 
          }else
          {
           Write-host "`nconnected successfully to host [$hostname]" -ForegroundColor Green  
          }         
    
     $log_bin=$MyData[1] 
    
     az mysql server show --ids "/subscriptions/$Subscription/resourceGroups/$RG/providers/Microsoft.DBforMySQL/servers/$hostname1" > $SingleServerInfo
     $ServerData= get-content "$SingleServerInfo" | ConvertFrom-Json
     
     #Checking Binary logging on Source single mySQL server, Needed to configure replication

     Write-host "Checking Binary logging on [$hostname]"
     If ($log_bin -match "ON")
     {
      Write-host "`nBinary logging is already enabled on the source MySql [$hostname]`n" -ForegroundColor YELLOW 
     }    
     Else
     {
      Write-host "`nReplication cant be configured. Binary logging is disabled on the source MySql [$hostname].`nKindly verify that binary logging is enabled by running ""SHOW VARIABLES LIKE 'log_bin';""" -ForegroundColor Red 
      Write-host "Refer: https://learn.microsoft.com/en-us/azure/mysql/single-server/how-to-data-in-replication`n" -ForegroundColor Blue
     "Replication cant be configured. Binary logging is disabled on the source MySql [$hostname]. Kindly verify that binary logging is enabled by running ""SHOW VARIABLES LIKE 'log_bin';""" >> $Log_File
     $Output_data += New-Object psobject -Property @{Host_Name=$hostname;Status="Failed";Error_msg="Binary logging is disabled on the source MySql [$hostname]"}
      #$Output_data | select-object Host_Name, Status, Error_msg | Export-CSV -NoTypeInformation -Path $progressfile
     continue;
     }
     
    $sslEnforcement=$ServerData[0].sslEnforcement
  }
   
  if($null -eq $mysqlFlexi){
        Write-host "Destination column for approved row can't be blank. Please supply Flexible server name and re-run the script again!!!" -ForegroundColor Red
        exitcode
        } 
      
 
 #Checking for server for Data encryption using CMK 
   az account set -s $Subscription
 $keyIdentifier=az mysql server key list --name $hostname1 -g $RG |ConvertFrom-Json

If ($keyIdentifier -ne $null)
{
$keyIdentifier=$keyIdentifier.uri

$KeyVault=$keyIdentifier.split("/")[2].split(".")[0]

write-host "MySQL Single server [$hostname1] is using Data encryption with CMK `nThis Server Migration to Flexible Server will require Manage identity as an access policy with key permissions 'Wrap Key', 'Unwrap Key', 'Get' and 'List' "

Write-host "Please refer for more details: https://learn.microsoft.com/en-us/azure/mysql/single-server/how-to-data-encryption-cli"
Write-host "https://learn.microsoft.com/en-us/azure/mysql/migrate/migrate-single-flexible-mysql-import-cli"
Write-Host "`nPlease select from option below to migrate this server" -ForegroundColor Green
Write-Host "===================================================================="
Write-Host "1. Create Managed Identity with key permissions get/unwrapKey/wrapKey"
Write-Host "2. Enter already created Managed Identity name with above permission"
Write-Host "3. Skip processing this Server"
$validInputs = "1", "2", "3"
do {
    $inputresponse = Read-Host -Prompt "`nEnter value"
    if(-not $validInputs.Contains($inputresponse)){write-host "Please select the choice between 1 - 3"}
} until ($validInputs.Contains($inputresponse))
$taskToPerform = $inputresponse

$identityInfo = "2"
if($identityInfo.Contains($taskToPerform))
{
$identity = Read-Host -Prompt "Enter identity name:"
write-host "using identity [$identity]"

}
$identityInfo = "1"
if($identityInfo.Contains($taskToPerform))
{
$identity = Read-Host -Prompt "Enter identity name to create"
write-host "creating Managed identiry [$identity]"
$identityPrincipalId=az identity create -g $RG --name $identity --query principalId -o tsv
az keyvault set-policy -g $RG -n $KeyVault --object-id $identityPrincipalId --key-permissions wrapKey unwrapKey get list

#$identityPrincipalId=az identity SHOW -g $RG --name $identity --query principalId -o tsv

}

$exitvalue = "3"
if($exitvalue.Contains($taskToPerform))
{
 $Output_data += New-Object psobject -Property @{Host_Name=$hostname;Status="Skipped";Error_msg="Server was skipped for Migration"}  
continue
}


$CMKParameter=" --identity $identity --key $keyIdentifier"
#Write-host "CMKParameter is "$CMKParameter
}


# Provisioning Flexible server 
   
    Write-host "Cloning host [$hostname] to Flexi server [$mysqlFlexi]" -ForegroundColor Green

    $joblist+=$hostname1
    
    #Write-Host $joblist  
            # Record provisiong start time  
    Write-host "`n----------Start Time::$(Get-Date -format 's')-----------`n"
     
    Write-host "Provisioning Flexible server [$mysqlFlexi] is in progress..." -ForegroundColor Blue

    #Write-host "`n--------------------------------------------------------`n"

    #$Az_import += '; $Success=$? '
    if ($CMKParameter -eq "")
    {
    "$Az_import `n">>$Log_File
    }
    else
    {
     "$Az_import $CMKParameter `n">>$Log_File
    }
    $Az_import += " 2>&1 >> $Log_File"

    #Invoke-Expression "$Az_import"
  
    $thread=Start-Job  -ScriptBlock ${function:Config_MySQL}  -Name "$hostname1" -ArgumentList $Az_import,$Log_File,$Subscription,$uid,$DB_Name,$SSL,$pass,$cert,$port,$SingleServerInfo,$FlexServerInfo,$destinationFilePath, $sslEnforcement,$Mig_mode,$progressfile,$CMKParameter
  

    
}



    $Progress_data=$Output_data

    IsFileNotAccessible($progressfile)
    $Progress_data | select-object Host_Name, Status, Error_msg| Export-CSV -NoTypeInformation -Path $progressfile
    

    #$runningCount=$thread.count
     
     $runningCount=(Get-Job -State Running).count
   
     $joblistR=Get-Job -State Running
     if($runningCount -gt 0){
    write-host "`nBelow are list of running jobs..." -ForegroundColor Yellow

    $InProgressJob=0

    
     Get-Job | Select-Object Id,name,state ,location |  Format-Table -AutoSize -wrap
     Write-host "Checking job(s) status in every 30s. Whenever a job changes its state, you will see it below and also at location [$progressfile]..." -ForegroundColor Yellow
    }
    while($runningCount -gt 0)
     {
       
       
       if ($runningCount -ne $InProgressJob){
        if ( $InProgressJob -ne 0)
        {
        Get-Job | Select-Object Id,name,state ,location |  Format-Table -AutoSize -wrap
        }
        #write-host "runningCount" $runningCount
        #write-host "InProgressJob" $InProgressJob

        $Progress_data=@()
        foreach($job in $joblistR)
        {
             $Progress_data += New-Object psobject -Property @{Host_Name=$job.Name;Status=$job.state;Error_msg="NA"}
        }
        $Progress_data +=$Output_data

        IsFileNotAccessible($progressfile)
        $Progress_data |select-object Host_Name, Status, Error_msg| Export-CSV -NoTypeInformation -Path $progressfile
         $InProgressJob=$runningCount
        #Write-host "Checking job(s) status in every 30s. Any change in job state will appear below or updated at location [$progressfile]..." -ForegroundColor Yellow
        
       }        else{

       
         
        Start-Sleep 30
        $runningCount=(Get-Job -State Running).count
        }
        
    }
  
      
   
      

#while((Get-Job -State Running).count){
#Get-Job | ? {$_.State -eq 'Complete' -and $_.HasMoreData} | % {Receive-Job $_}
#start-sleep -seconds 1

  $Content1=@()
  $Content=@()

  foreach($job in $joblist)
  {
    $log_file1=$folder+"\Output\"+$job+"_"+"$Outdate.log"
    $Content=Get-Content $log_file1 | Select-Object -last 1
    $Content1 = $Content.replace(';',"`n").replace('@{',"").replace('}',"") | ConvertFrom-StringData
    $Output_data += New-Object psobject -Property $Content1
   #$Output_data | select-object Host_Name, Status, Error_msg | Export-CSV -NoTypeInformation -Path $progressfile
  Write-host "----------------------------------------------------------------------------------------------"
  Write-host "Provisioning log of Flexible MySQL server for source single server:" $job -ForegroundColor Blue
  Write-host "----------------------------------------------------------------------------------------------`n"

  Receive-Job -Name $Job
  #if (Test-Path $destinationFilePath) { Remove-Item $destinationFilePath} 
  }
 



 #Get-Job | Receive-Job  
  
#Write-host "joboutput" $joboutput
Remove-Job *
Write-host "----------------------------------------------------------------------------------------------"
Write-host "Refer below for final Status table"
Write-host "----------------------------------------------------------------------------------------------"
 
 IsFileNotAccessible($progressfile)
   
 $Output_data | select-object Host_Name, Status, Error_msg | Export-CSV -NoTypeInformation -Path $progressfile
Write-Host ($Output_data | Select-Object Host_Name,Status,Error_Msg| Format-Table -AutoSize -wrap| Out-String) 

#write-host $out1



    Stop-Transcript


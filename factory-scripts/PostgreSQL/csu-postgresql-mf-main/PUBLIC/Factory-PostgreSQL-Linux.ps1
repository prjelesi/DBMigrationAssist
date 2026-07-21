#---------------------------------------------------------------------------------------------------------------------------*
#  Purpose        : Script to fetch Information from PostgreSQL.
#  Schedule       : Ad-Hoc / On-Demand
#  Date           : 15-June-2023
#  Author         : Rackimuthu Kandaswamy , Sireesha , Lekshmy , Arun, Madan
#  Version        : 1.1
#   
#  INPUTS         : Server List and other parameters in CSV file; SSL_Modes = allow, disable, prefer, require, verify-ca, verify-full
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
# Powershell.exe -File ./Factory-PostgreSql_Server_Automation_V1.1.ps1
#
#change Log 31st July 2023 Sireesha Error Handling and PSQL validation 
#change Log 10th Oct 2023 Lekshmy : Added Option 2 for detailed info gathering and output format for option 1 to CSV multiple workbooks


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

$folder = $PSScriptRoot
$postgrespath = which psql
$Triggerpsql_File_Path=$Folder+"/Trigger_psql.bat"
$date = Get-Date -Format "yy-dd-MM-hh-mm"
$Log_Name= $Host_Name.replace(".", "_")
$DbGather_Path=$Folder+"/PostgreSQL_Templates/pg_db_gather_db.sql"
$DbGather_Server_Path=$Folder+"/PostgreSQL_Templates/pg_db_gather_server.sql"
$DetailedInfo_Path=$Folder+"/PostgreSQL_Templates/pg_db_maintenance.sql"
$DbList_path=$Folder+"/PostgreSQL_Templates/DB_List.sql"



#---------------------------------------------------------PROGRAM BEGINS HERE----------------------------------------------------------


CLS
write-host "                                                                                       " -BackgroundColor DarkMagenta
Write-Host "       Welcome to Factory - PostgreSQL_Info_Gathering_Automation                           " -ForegroundColor white -BackgroundColor DarkMagenta
write-host "                  (OSS DB Migration factory)                                           " -BackgroundColor DarkMagenta
write-host "                                                                                       " -BackgroundColor DarkMagenta
Write-Host " "

if ($postgrespath -like "*/psql*") {
	Write-Host "PostgreSQL exists. Continuing execution..." -ForegroundColor Green
}
else {
	Write-Host "PostgreSQL does not exists. Please install PostgreSQL and re-execute the script" -BackgroundColor Red
	exit
}

Write-Host "Please select the assessment operation to perform" -ForegroundColor Green
Write-Host "===================================================================="
Write-Host "1. Perform PostgreSQL server Information gathering"
Write-Host "2. Exit"

$validInputs = "1","2"
do {
    $inputresponse = Read-Host -Prompt "Enter value"
    if(-not $validInputs.Contains($inputresponse)){write-host "Please select the choice between 1 - 2"}
} until ($validInputs.Contains($inputresponse))

$taskToPerform = $inputresponse

$exitvalue = "2"
if($exitvalue.Contains($taskToPerform))
{
exitcode
}

#$DetailedInfo = "2"
<#if($DetailedInfo.Contains($taskToPerform))
{
	
Write-Host "======================================================================================= "

Write-Host "CAUTION! :- "  -ForegroundColor Red  -BackgroundColor yellow
Write-Host "Please make sure this option is selected during OFF BUSINESS HOURS or LOW PEAK  Period so as to avoid DATABASE PERFORMANCE " -ForegroundColor Red  -BackgroundColor yellow
$validInputs_Yes_No = @("y", "n","Y","N")
     
Write-Host "Please press 'Y' to continue detailed information gathering.Press 'N' to terminate the execution (Y or N) " -ForegroundColor Green
Write-Host "======================================================================================="
do {
    $response="N"
    $response = read-host "Please provide your inputs"
    if(-not $validInputs_Yes_No.Contains($response)){write-host "Please Enter a valid input (Y or N )"}
    
}until ($validInputs_Yes_No.Contains($response.ToLower()))

if ($response -eq "n")
{
    exitcode
}          

Write-Host "======================================================================================= "
}#>

$today_date=Get-Date -Format "MM_dd_yyyy_HH_mm"
Start-Transcript -path  $folder/Logs/Factory-PostgreSQL_Info_Gathering_Automation_Transcript_$today_date.txt -Append

Write-Host "======================================================================================= "
createFolder $folder/Downloads/
createFolder $folder/Output/

Write-Host ""
Write-Host "======================================================================================= "
Write-Host "Input Section "   -ForegroundColor Green


# Read the input config CSV and validate
$inputfile = $PSScriptRoot+"/Factory_PostgreSQL_Server_Input_file.csv"
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

         #$ConfigList = $Approved_Rows | Group-Object -Property 'Host_Name' | ForEach-Object {
   # $_.Group | Select-Object -First 1
	#}
	
		$ConfigList = $Approved_Rows | Group-Object -Property Host_Name, Port | ForEach-Object {
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

        Write-Host "CSV validation is done successfully " 
        }
     else {Write-Host "There are missmatches in the CSV column . Kindly check and retrigger the automation "  -ForegroundColor Red 
           exitCode}
  }


    ##Input CSV validation is done


	Write-Host "=======================================================================================" 
    Write-Host "Here are the List of the Hosts the automation will proceed based on the user selection -" -ForegroundColor Green
    Write-Host "=======================================================================================" 

	$db_Selection_Display=@()
    $validInputs_Yes_No = @("y", "n","Y","N")

	Write-Host ($ConfigList | select Host_Name | Format-Table | Out-String)
  
	Write-Host "=======================================================================================" 
    Write-Host "Please enter Y if you wish to continue , otherwise please press N to exit" -ForegroundColor Green
    Write-Host "=======================================================================================" 
    #$response1="n"

    do {
    $response1 = read-host "Please provide your inputs"
    if(-not $validInputs_Yes_No.Contains($response1)){write-host "Please Enter a valid input (Y or N )"}
    
    }until ($validInputs_Yes_No.Contains($response1.ToLower()))

    if ($response -eq "n")
    {
        exitcode
    }          
	
	$i = 0
	$Output_data =@()
    $Global:project_name = ""
    
    $Global:project_name = Read-Host "`nEnter the project name "

	foreach ($row_Content in $ConfigList)
	{
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
	
		$Password=$row_Content.'Password'
		if ([string]::IsNullOrWhitespace($Password)){
            $credentials = Get-Credential -UserName $User_ID -Message "Please provide valid credentials for $Host_Name"
            $Password = $credentials.GetNetworkCredential().Password
            if ([string]::IsNullOrWhitespace($Password)){
                Write-Host "'Password' is not valid in the Server_List worksheet. Kindly check and retrigger the automation  "  -ForegroundColor Red 
                Continue
            }
			
		}

		$DB_Name=$row_Content.'DB_Name'
		if ([string]::IsNullOrWhitespace($DB_Name)){
			Write-Host "'DB_Name' is not valid in the Server_List worksheet. Kindly check and retrigger the automation  "  -ForegroundColor Red 
			Continue
		}

        $SSL=$row_Content.'SSL_Mode'
		if(($SSL -eq "") -or ($SSL -eq $null) -or ($SSL -eq " ")) {
		
			Write-Host "'SSL Mode' is not valid in the Server_List worksheet. Kindly provide the right mode and retrigger the automation  "  -ForegroundColor Red 
			Continue
        }

		$Port=$row_Content.'Port'
		#if(($Port -eq "") -or ($Port -eq $null) -or ($Port -eq " ")) {
		if ([string]::IsNullOrWhitespace($Port)){
			$Port = 5432
			#Write-Host "'Port' is not valid in the Server_List worksheet. Kindly check and retrigger the automation  "  -ForegroundColor Red 
			Continue
		}
    
    #$DBList_Log_File=$Folder+"/Output/"+$Global:project_name+"_"+$Host_name+"$DBName.log"
	$DBList_Log_File      = "$Folder/Output/$($Global:project_name)_$Host_Name`_$Port`_DBList.log"
    #$errDBList_Log_File=$Folder+"/Output/"+$Global:project_name+"_"+$Host_name+"$DBName.err"
	$errDBList_Log_File   = "$Folder/Output/$($Global:project_name)_$Host_Name`_$Port`_DBList.err"
    #createFolder $Folder/Output/$Host_Name

    #Validating psql
    #Write-Host "Checking for PSQL path" -ForegroundColor white
    #$psql_validdation_file_path=$Folder+"/psql_validation.bat"
    $psql_Log_File=$Folder+"/Output/psql_validation.log"
    $errpsql_Log_File=$Folder+"/Output/psql_validation.err"
    # $psql_OP = Start-Process -FilePath $psql_validdation_file_path  -ArgumentList "$psql_Log_File"-Wait -WindowStyle Hidden
    $psqlCommand="psql --version"
    Invoke-Expression "$psqlCommand 2>&1 | Out-File -FilePath $psql_Log_File"
    $stat = $LASTEXITCODE
    Write-Output "Last operation status: $stat"
    If( $stat -ne 0)
    {
       # seems to have failed
       Write-Host "Failed to validate psql location" -ForegroundColor RED
       $errorMessage = $Error[0].Exception.Message
       $errorMessage | Out-File -FilePath $errpsql_Log_File -Append
       $error_m=Get-content -path $errpsql_Log_File | out-string
       continue
    }

    $error_msg=Get-content -path $psql_Log_File | out-string
    
    $error_msg1=$error_msg.tolower()

    if (Test-Path $psql_Log_File) {
    
    if ($error_msg1 -like ("*is not recognized as an internal or external command*")){
    #Write-host $path_check -ForegroundColor red
    write-host "Either Postgresql client tool is not installed on the server or psql Path is not set in environment variable" -ForegroundColor red 
    write-host ""
    write-host "Please configure as appropriate and re-run automation script"
    exitcode
    }
    else
    {
        Write-host "Psql validated successfully"  -ForegroundColor green
    }
    

    }else
    {
        write-host "Error in validating psql" -ForegroundColor red
        Write-Host "Please check and re-run the script"
        exitcode
    }
    #Write-host ""

    Remove-Item $psql_Log_File
    <#$validInputs_Yes_No = @("y", "n","Y","N")
     
    Write-Host    "Please press Y to continue PostgreSQL Info-Gathering .Press N to terminate the execution " -ForegroundColor Green
    Write-Host "======================================================================================="
    
    do {
    $response = read-host "Please provide your inputs"
    if(-not $validInputs_Yes_No.Contains($response)){write-host "Please Enter a valid input (Y or N )"}
    
    }until ($validInputs_Yes_No.Contains($response.ToLower()))

    if($response -eq "n"){exitcode}    
    	##### Initiating Server info gathering
    #>
	$ServerAutomation = "1"
	if($ServerAutomation.Contains($taskToPerform))
	{

		$DBParam_Log_File=$Folder+"/Output/$Host_Name_DBlog_$Log_Name.csv"

		#Execute PostgreSQL command 
		Write-Host "=======================================================================================" 

                #Intiating Database name extraction using /l

              Write-Host "Extracting Database details from" $Host_Name`_$Port`  
        
		#$DBList_OP = Start-Process -FilePath $Triggerpsql_File_Path -ArgumentList "$User_ID", "$Host_Name", "$Password","$DB_Name" , "$Port", "$DbList_path" , "$DBList_Log_File", "$SSL" -Wait -PassThru -WindowStyle Hidden
                $env:PGPASSWORD = $Password
                $escapedDBCommand = "`"dbname=$DB_Name sslmode=$SSL`""
                $psqlCommand="psql --username=$User_ID --host=$Host_Name --port=$Port --file=$DbList_path $escapedDBCommand"
                Invoke-Expression "$psqlCommand 2>&1 | Out-File -FilePath $DBList_Log_File"
                $stat = $LASTEXITCODE
                Write-Output "Last operation status: $stat"
                If( $stat -ne 0)
                {
                   # seems to have failed
		   Write-Host "Failed to connect database server on $Host_Name and find the issue in the location $Folder/Output folder" -ForegroundColor RED
                   $errorMessage = $Error[0].Exception.Message
                   $errorMessage | Out-File -FilePath $errDBList_Log_File -Append
		   $error_m=Get-content -path $DBList_Log_File | out-string
		   $Output_data += New-Object psobject -Property @{Host_Name=$Host_Name;Status="FAILED";LOG_File_Location=$DBList_Log_File;Error_Msg=$error_m}
		   $parameter_listing = "`nThe parameters are:`nUserID: $User_ID`nHostname: $Host_Name`nPassword:Kindly check in Input file`nDB_Name: $DB_Name`nPort: $Port`nSSL: $SSL"
		   Add-Content $DBList_Log_File $parameter_listing
		   continue
                }

                #$DBlogServerfile=$Folder+"/Output/" + $Global:project_name+ "_" + $Host_Name + "_Server" +".log"
				$DBlogServerfile      = "$Folder/Output/$($Global:project_name)_$Host_Name`_$Port`_Server.log"
                $env:PGPASSWORD = $Password
                $escapedDBCommand = "`"dbname=postgres sslmode=$SSL`""
                $psqlCommand="psql --username=$User_ID --host=$Host_Name --port=$Port --file=$DbGather_Server_path $escapedDBCommand"
                Invoke-Expression "$psqlCommand 2>&1 | Out-File -FilePath $DBlogServerfile"
                Remove-Item Env:/PGPASSWORD

     	        #excluding default databases
	
		$logcontent=@()
		$logcontent= Get-Content $DBList_Log_File |  Where-Object {$_ -notmatch '-------------------'} | Select -Skip 1 |  Where-Object {$_ -notmatch 'template'} |  Where-Object {$_ -notmatch 'azure_maintenance'} |  Where-Object {$_ -notmatch 'azure_sys'} |Select -SkipLast 2
        
		#$data=$logcontent | ConvertFrom-Csv -Delimiter "|" | ConvertTo-Json
		#$newdata= $data | ConvertFrom-Json
		foreach ($i in $logcontent)
		{
			#for each custom database
			$PostGres_DB_Name= $i #.'Name ' 
			$PostGres_DB_Name=$PostGres_DB_Name.Trim()
        
			#Capturing server details
			Write-host "Initiating Info-Gathering for  $Host_Name`_$Port` : $PostGres_DB_Name Database" -ForegroundColor Green
                        Write-Host $Global:project_name -ForegroundColor Magenta
			#$DBlogfile=$Folder+"/Output/" + $Global:project_name+ "_" + $Host_Name + "_" + $PostGres_DB_Name +".log"
			$DBlogfile            = "$Folder/Output/$($Global:project_name)_$Host_Name`_$Port`_$PostGres_DB_Name.log"
			$errDBlogfile         = "$Folder/Output/$($Global:project_name)_$Host_Name`_$Port`_$PostGres_DB_Name.err"
                        #$errDBlogfile=$Folder+"/Output/" + $Global:project_name+ "_" + $Host_Name + "_" + $PostGres_DB_Name +".err"
						
                      #  $OutputFile=$Folder+"/Output/$Host_Name_Output_$PostGres_DB_Name.log"
						$OutputFile           = "$Folder/Output/$Host_Name`_$Port`_Output_$PostGres_DB_Name.log"
			#$Database_OP = Start-Process -FilePath $Triggerpsql_File_Path -ArgumentList "$User_ID", "$Host_Name", "$Password","$PostGres_DB_Name" , "$Port",  "$DbGather_Path" , "$DBlogfile", "$SSL" -Wait -WindowStyle Hidden
                        $env:PGPASSWORD = $Password
                        $escapedDBCommand = "`"dbname=$PostGres_DB_Name sslmode=$SSL`""
                        $psqlCommand="psql --username=$User_ID --host=$Host_Name --port=$Port --file=$DbGather_path $escapedDBCommand"
                        Invoke-Expression "$psqlCommand 2>&1 | Out-File -FilePath $DBlogfile"
                        Remove-Item Env:/PGPASSWORD
                }

        }
	
	#Option 2 for detailed info gathering
	#$DetailedInfo = "2"
	<#if($DetailedInfo.Contains($taskToPerform))
	{
		
	$DetailedInfo_Log_File=$Folder+"/Output/$Hostname_DetailedInfo_$Log_Name.csv"
	$DetailedDB=@()

        $folder = $PSScriptRoot
        $Triggerpsql_File_Path=$Folder+"/Trigger_psql.bat"

        #$DBList_OP = Start-Process -FilePath $Triggerpsql_File_Path -ArgumentList "$User_ID", "$Host_Name", "$Password","$DB_Name" , "$Port", "$DbList_path" , "$DBList_Log_File", "$SSL" -Wait -WindowStyle Hidden
        $env:PGPASSWORD = $Password
        $escapedDBCommand = "`"dbname=$DB_Name sslmode=$SSL`""
        $psqlCommand="psql --username=$User_ID --host=$Host_Name --port=$Port --file=$DbList_path $escapedDBCommand"
        Invoke-Expression "$psqlCommand 2>&1| Out-File -FilePath $DBLIST_Log_File"
        Remove-Item Env:/PGPASSWORD

		#excluding default databases
	
		$logcontent=@()
		$logcontent= Get-Content $DBList_Log_File |  Where-Object {$_ -notmatch '-------------------'} | Select -Skip 1 |  Where-Object {$_ -notmatch 'template'} |  Where-Object {$_ -notmatch 'azure_maintenance'} |  Where-Object {$_ -notmatch 'azure_sys'} |Select -SkipLast 2

		#$data=$logcontent | ConvertFrom-Csv -Delimiter "|" | ConvertTo-Json
		#$newdata= $data | ConvertFrom-Json
		foreach ($i in $logcontent)
		{
			#for each custom database
			$PostGres_DB_Name=$i #.'Name ' 
			$PostGres_DB_Name=$PostGres_DB_Name.Trim()
        
			#Capturing server details
			Write-host "Initiating Detailed Info-Gathering for  $Host_Name : $PostGres_DB_Name Database" -ForegroundColor Green
			$DBfile=$Folder+"/Output/" + $Global:project_name + "_DetailedInfo_" + $Host_Name + "_" +$PostGres_DB_Name + ".log"
                        $errDBfile=$Folder+"/Output/" + $Global:project_name + "_DetailedInfo_" + $Host_Name + "_" +$PostGres_DB_Name + ".err"
			#$DB_Detailed = Start-Process -FilePath $Triggerpsql_File_Path -ArgumentList "$User_ID", "$Host_Name", "$Password","$PostGres_DB_Name" , "$Port",  "$DetailedInfo_Path" , "$DBfile", "$SSL" -Wait -WindowStyle Hidden
                        $env:PGPASSWORD = $Password
                        $escapedDBCommand = "`"dbname=$PostGres_DB_Name sslmode=$SSL`""
                        $psqlCommand="psql --username=$User_ID --host=$Host_Name --port=$Port --file=$DetailedInfo_path $escapedDBCommand"
                        Invoke-Expression "$psqlCommand 2>&1 | Out-File -FilePath $DBfile"
                        Remove-Item Env:/PGPASSWORD
		}
       }#>
       #Remove-Item $DBList_Log_File


       if (Test-Path $DBList_Log_File) {
			$size = Get-Content -Path $DBList_Log_File -Raw 
			if($size -match "datname") {
				Write-host "Information Gathered is stored at "$DBList_Log_File
				Write-host "Info-Gathering Successfully  completed for "$Host_Name"_$Port" -ForegroundColor Green
    
				$Output_data += New-Object psobject -Property @{Host_Name=$Host_Name;Status="SUCCESS";LOG_File_Location=$DBList_Log_File;Error_msg="NA"}
			}
			else{
			$error_msg=Get-content -path $DBList_Log_File | Out-String
			$Output_data += New-Object psobject -Property @{Host_Name=$Host_Name;Status="FAILED";LOG_File_Location=$DBList_Log_File;Error_Msg=$error_msg}
			write-host $error_msg -ForegroundColor red  
			Write-host "Error details are stored at "$DBList_Log_File
			
			if ($error_msg -like ("*is not recognized as an internal or external command*"))
			{
				write-host "Either Postgresql client tool is not installed on the server or psql Path is not set in environment variable" -ForegroundColor red 
				exitcode
			}
	
			}
		}
		else {
			$Output_data += New-Object psobject -Property @{Host_Name=$Host_Name;Status="FAILED";LOG_File_Location="NA";Error_Msg="NA"}
		}

    }
         #Remove-Item $DBList_Log_File

		Write-Host "" 
        Write-Host "======================================================================================="  
        Write-Host "Below is The final status of PostgreSQL Script Execution "  -ForegroundColor Green  
        Write-Host "======================================================================================="

        #Write-Host ($Output_data | select Host_Name,Status,LOG_File_Location,Error_Msg| Format-Table -AutoSize -wrap| Out-String)  
        Write-Host ($Output_data | select Host_Name,Status,Error_Msg| Format-Table -AutoSize -wrap| Out-String)  

		if ($Output_data -ne "")
		{
			#$Output_data | select Host_Name,Status,LOG_File_Location,Error_Msg | Export-Csv $PSScriptRoot/Output/$Host_Name/Server_Status.xlsx -WorksheetName "PostgreSQL_Server" -TableStyle Medium16 -title "PostgreSQL Server Status" -TitleBold    
		}

Stop-Transcript
exitcode

#---------------------------------------------------------------------------------------------------------------------------*
#  Purpose        : Script for Information gathering of Azure MySQL Single Server
#  Schedule       : Ad-Hoc / On-Demand
#  Date           : 19-July-2023
#  Author         : Rackimuthu Kandaswamy , Sireesha , ArunKumar , Saby , Lekshmy MK, Madan Agrawal
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
# Powershell.exe -File .\Factory-MySQL-CLI-Windows.ps1
#
<#
    Change Log
    ----------
•	Customer consent to install Import-Csv PS Module and Azure CLI
•	Excluded Flexi server Azure CLI commands.
•	Excluded Azure CLI commands Json file generation for single servers except Server list.
•	Incorporated Vcore column in INPUT CSV  Sheet  Factory-MySQL_Server_Input_file.csv file (Server_List csv)
•	Incorporated servername in DB_List, Config_Details,AD Admin and Firewall-rule List  CLI commands output in output.csv
•	No column Filter applied when exporting AZURE CLI Commands output to output.csv file
•	Included az MySQL server replica list CLI
•	Script now can be run directly without wrapper.
•	Output files creation verification added at end of script.
•	-NoTypeInformation to suppress the first line from CSVs.        
•	Skip execution for servers where server state is not "Ready" to suppress error message and to gain performace.
•	Progress bar addition with server in progress
•	Inlcuded multiple subscription features
#>
Set-ExecutionPolicy Bypass -Scope currentuser
CLS


#---------------------------------------------------------PROGRAM BEGINS HERE----------------------------------------------------------

write-host "                                                                            " -BackgroundColor DarkMagenta
Write-Host "                    Welcome to Factory-MySQL_Info_Gathering_Automation          " -ForegroundColor white -BackgroundColor DarkMagenta
write-host "                     (OSS DB Migration Factory)                             " -BackgroundColor DarkMagenta
write-host "                                                                            " -BackgroundColor DarkMagenta
Write-Host " "

$folder = $PSScriptRoot
$mysqlpath = where.exe mysql
$today_date=Get-Date -Format "MM_dd_yyyy_HH_mm"
$azpath = ";C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin"													
 Write-Host "==============================================================================================================" 
 Start-Transcript -path  $folder\Logs\Factory-MySQL_Info_Gathering_Automation_Transcript_$today_date.txt  -Append
 Write-Host "==============================================================================================================" 

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
      $createfolder=New-Item $newFolder -ItemType Directory
        Write-Host "-$newFolder folder created..."
    }
}

if ($mysqlpath -like "*\mysql*") {
	Write-Host "MySQL exists. Continuing execution..." -ForegroundColor Green
}
else {
	Write-Host "MySQL is not installed or its path is not in the environment variables. Please install MySQL, add its path to the environment variables, and rerun the script." -BackgroundColor Red
	break
}

createFolder $folder\Downloads\
createFolder $folder\Logs\
createFolder $folder\Output\
createFolder $folder\Output\Single\


# Read the input config Csv and validate
$inputfile = $PSScriptRoot+"\Azure_Subscription.csv"

Write-Host "Input file is $inputfile " -ForegroundColor Green
 Write-Host "==============================================================================================================" 


if (-not(Test-Path -Path $inputfile -PathType Leaf)) {
    try {    
         Write-Host "==============================================================================================================" 
         Write-Host "Unable to read the input file [$inputfile]. Check file & its permission...  "  -BackgroundColor Red
         Write-Host "==============================================================================================================" 
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
         $ConfigList = Import-CSV -Path $inputfile  
         }

         catch {
         Write-Host "==============================================================================================================" 
         Write-Host "The file [$inputfile] does not have the woksheet named Azure_Subscription "  -BackgroundColor Red 
         Write-Host "==============================================================================================================" 
         Write-Host "Please see the error below & MySQL CLI WINDOWS has been stopped          "  
         throw $_.Exception.Message
         exitcode
        }

}    

 
 $ColumnList=$ConfigList | Get-Member -MemberType NoteProperty | %{"$($_.Name)"}
     if (($ColumnList.Contains("Tenant")) -and
        ($ColumnList.Contains("Subscription_ID"))){

        Write-Host "Csv validation is done successfully " 
        }
     else {Write-Host "There are mismatches in the Csv column . Kindly check and retrigger the automation "  -BackgroundColor Red
           exitCode}


Unblock-File $folder/Validation_Scripts/Check_PowerShell_Version.ps1
Unblock-File $folder/Validation_Scripts/azurecli.ps1
      
# Check PowerShell version
$Validation=@()
$Outfiledata=@()
$Outputexcel=@()
$DBListData=@()
$AdAdminData=@()

$global:alldata =@()
$global:row=@{}
$FWData=@()
$ServerConfigData=@()
$Validation+=& "$folder/Validation_Scripts/Check_PowerShell_Version.ps1"
$Validation+=& "$folder/Validation_Scripts/azurecli.ps1"

Write-Host "==============================================================================================================" 
Write-Host "Below are the Validation Results"  -ForegroundColor Green  
Write-Host "==============================================================================================================" 
Write-Host ($Validation | select Validation_Type,Status,Comments | Format-Table | Out-String)

If($Validation.Status.Contains("FAILED"))
{
 Write-Host "There are errors during validation . Terminating the execution ."  -ForegroundColor Red
 exitcode  
}


#Function to convert json value to hashtable

    function ConvertTo-Hashtable {
    [CmdletBinding()]
    [OutputType('hashtable')]
    param (
        [Parameter(ValueFromPipeline)]
        $InputObject
          )

        process {
        if ($null -eq $InputObject) 
        {
            return $null
         }
        
        if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string])
        {
            $collection = @(
                foreach ($object in $InputObject) {
                    ConvertTo-Hashtable -InputObject $object
                }
                )

         Write-Output -NoEnumerate $collection
        }
        elseif ($InputObject -is [psobject]) 
        {
            $hash = @{}
            
            foreach ($property in $InputObject.PSObject.Properties) 
            {
                $hash[$property.Name] = ConvertTo-Hashtable -InputObject $property.Value
            }
            
             $hash
        } 
        else 
        {
            $InputObject
        }
        }
    }

    #Functions to fetch the json paths
    function Factory-Read-Hashtable ([Hashtable]$InputHashTable){
	foreach ($h in $InputHashTable.GetEnumerator() ){
		if ($h.Value -is [Array]){
			Factory-Read-Nested-Array $h.Name $h.Value
		}elseif ($h.Value -is [Hashtable]){
			Factory-Read-Nested-Hashtable $h.Name $h.Value
		}else{
                       $key = $h.Name
                       if ($global:row.ContainsKey($key)) {
                         $global:row[$key] = $h.Value
                       }
                       else {   
			 $global:row.Add($key, $h.Value)
                       }
		}
	}
	$global:alldata += $global:row
	$global:row =@{}
    }

    function Factory-Read-Nested-Hashtable ([String]$prefix,[Hashtable]$InputNestedHashTable){
	foreach ($h in $InputNestedHashTable.GetEnumerator()){
		if ($h.Value -is [Array]){
			Factory-Read-Nested-Array $h.Name $h.Value
		}elseif ($h.Value -is [Hashtable]){
            $newPrefix=-join($prefix,".",$h.Name)
			Factory-Read-Nested-Hashtable $newPrefix $h.Value
		}else{
                       $key = -join @($prefix, ".", $h.Name)
                       if ($global:row.ContainsKey($key)) {
                         $global:row[$key] = $h.Value
                       }
                       else {   
			 $global:row.Add($key, $h.Value)
                       }
		}
	    }
    }

    function Factory-Read-Array ([Array]$InputArray){
    foreach ($a in $InputArray){
		if($a -is [Hashtable]){
			Factory-Read-Hashtable $a
		}elseif ($a.Value -is [Array]){
		    Factory-Read-Nested-Array $a.Name $a.Value 
		}elseif ($a -is [Array]){
			Factory-Process-Nested-Array $null $a	
		}elseif($a.Value -is [Hashtable]){
			Factory-Read-Nested-Hashtable $a.Name $a.Value
		}else{
			Write-Host "Process-Array :$($a.Value.pstypenames)"
		}
	    }
    }

    function Factory-Read-Nested-Array ([String]$prefix,[Array]$InputArray){
    foreach ($a in $InputArray){
		if($a -is [Hashtable]){
		    Factory-Read-Nested-Hashtable $prefix $a
		}elseif ($a.Value -is [Array]){
			Factory-Read-Nested-Array $prefix $a.Value 
		}elseif ($a -is [Array]){
			Factory-Read-Nested-Array $prefix $a
		}elseif($a.Value -is [Hashtable]){
			Factory-Read-Nested-Hashtable $a.Name $a.Value
		}else{
			$global:row.Add(-join($prefix,".",$h.Name), $h.Value)
		}
	    }
    }


$tenant=$ConfigList.Tenant|Get-Unique

    if ([string]::IsNullOrWhitespace($tenant)){
Write-Host "Tenant listed Azure_Subscription worksheet is not valid. Kindly check and retrigger the automation  "  -BackgroundColor Red 
exitCode
}
elseif($tenant.count -gt 1)
{
Write-Host "Azure_Subscription.csv has multiple Tenant. This script doesn't support multiple Tenant but you can add multiple Subscription. `nKindly check and retrigger the automation for each Tenant separately."  -BackgroundColor Red 
exitCode

}
else
{
#AZ login to corresponsing Tenant and subscription
#$loginoutput=az login --tenant $tenant --only-show-errors
$loginoutput=az login --use-device-code --tenant $tenant --only-show-errors
}

if (!$loginoutput) 
{
    Write-Error "Error connecting to Tenant: $tenant"
    exitcode
}
$Subscriptions= $ConfigList.Subscription_ID|Sort-Object -Unique

      foreach ($Subscription in $Subscriptions)
  {
      $Serverdata=@()
    $db_data=@()
    $DBList=@()
    $ServerConf=@()
    $confdata=@()
    $ADAdmin=@()
    $Admin=@()
    $Firewall=@()
    $Replica=@()
    $CMKey=@()
    $MSDef=@()
    $SerEnd=@()
    $PvtEnd=@()
    $dbdata=@()




if ([string]::IsNullOrWhitespace($Subscription)){
Write-Host "$Subscription is not valid in the Azure_Subscription worksheet. Kindly check and retrigger the automation  "  -BackgroundColor Red 
continue
} 


    Write-Host "==============================================================================================================" 
    Write-Host "Processing Subscription: $Subscription" -ForegroundColor Green
    Write-Host "==============================================================================================================" 
   
    #AZ Connect to provided subscription
   
         $loginoutput=az account set --subscription $Subscription 2>&1
           $stat = $LASTEXITCODE


If( $stat -ne 0)
    {
       # seems to have failed
       #$errorMessage = $Error[0].Exception.Message
         Write-Host "Failed to execute [az account set --subscription $Subscription]" -ForegroundColor Red
         Write-Host "The file [$inputfile] does not have valid Subscription.`n"  -ForegroundColor Red
        continue
    }
      
  
    #Server list fetch for Single Server
    $Single_list_Out = az mysql server list | Out-File $folder\Output\Single\Single_Server_List.json -Append
    
    $ser_details = az mysql server list|ConvertFrom-Json
    
    $ser_list = az mysql server list |ConvertFrom-Json | ConvertTo-HashTable
    if($ser_list -is [Hashtable])
    {
        Factory-Read-Hashtable $ser_list
    }else
    {
	    Factory-Read-Array $ser_list
    }
    
    $Serverdata+=$global:alldata
    $global:alldata=@()
    $count=  $ser_details.count
    $k=1
    #Write-Host "=============================================================================================================="  
    if ($count -eq 0)
    {
     Write-Host "There is no MySQL single server on Subscription [$Subscription] for Tenant [$tenant]" -ForegroundColor Red
     Write-host "Please check Subscription on input file: Azure_Subscription.csv`n" -ForegroundColor Red
     #Write-Host "=============================================================================================================="  
  
    }
  foreach ($i in $ser_details)
  {
   
      #Updating input file with server details
      $ServerName= $i.name
      $Single_User_Name = $i.administratorLogin
      #createFolder $folder\Output\Single\$ServerName\
      $ser_rg = $i.resourceGroup  
      $domain_name = $i.fullyQualifiedDomainName
      $dom = $domain_name.Split(".")
      $ser_dom = $dom[0]
      $Logon_User=$Single_User_Name + "@" + $ser_dom
      $vcore=$i.sku.capacity
      $userVisibleState=$i.userVisibleState
      
      $per_complete=[math]::round($k/$count*100)
      Write-Progress -Activity "Server:$ServerName is in Progress..." -Status "$per_complete% Complete:" -PercentComplete $per_complete
      $k++
     
      # Write-Host "`nInformation gathering of Azure MySQL Single Server [$ServerName] is in progress..."  -ForegroundColor Yellow   
      $Outfiledata+=New-Object psobject -Property @{Host_Name=$domain_name;Resource_Group=$ser_rg;Port="3306";VCore=$vcore;Auth_Type="default";User_ID=$Logon_User;Password="";DB_Name="mysql";Tenant=$tenant;Subscription_ID=$Subscription;Approval_Status="No";SSL_Mode="PREFERRED"}
 
 if ($userVisibleState -match "Ready")
    {           
    try
    {    
    #DB List
    
    #$db_list = az mysql db list -g $ser_rg -s $ser_dom  | Out-File $folder\Output\Single\$ServerName\${ServerName}_Single_DB_List.json               
    $dbdata = az mysql db list -g $ser_rg -s $ser_dom | ConvertFrom-Json | ForEach-Object { $_ | Add-Member -MemberType NoteProperty -Name 'Servername' -Value $ServerName -PassThru} | ConvertTo-Json
    $db_data= $dbdata  |ConvertFrom-Json |  ConvertTo-HashTable
    if($db_data -is [Hashtable])
    {
        Factory-Read-Hashtable $db_data
    }else
    {
	    Factory-Read-Array $db_data
    }
    $DBList+=$global:alldata
    $global:alldata=@()
   
    #Server Configuration
    
    #$conf_list = az mysql server configuration list -g $ser_rg --server-name $ser_dom | Out-File $folder\Output\Single\$ServerName\${ServerName}_Single_Server_Configuration.json
    $confdata = az mysql server configuration list -g $ser_rg -s $ser_dom | ConvertFrom-Json| ForEach-Object { $_ | Add-Member -MemberType NoteProperty -Name 'Servername' -Value $ServerName -PassThru} | ConvertTo-Json
    $confdata = $confdata|ConvertFrom-Json | ConvertTo-HashTable
    if($confdata -is [Hashtable])
    {
        Factory-Read-Hashtable $confdata
    }else
    {
	    Factory-Read-Array $confdata
    }
    
    $ServerConf+=$global:alldata
    $global:alldata=@()

    #AD Admin
    
    #$ad_admin = az mysql server ad-admin list -g $ser_rg -s $ser_dom | Out-File $folder\Output\Single\$ServerName\${ServerName}_Single_AD_Admin_List.json
    $ADAdmin=az mysql server ad-admin list -g $ser_rg -s $ser_dom | ConvertFrom-Json| ForEach-Object { $_ | Add-Member -MemberType NoteProperty -Name 'Servername' -Value $ServerName -PassThru} | ConvertTo-Json
    $ADAdmin = $ADAdmin|ConvertFrom-Json | ConvertTo-HashTable
    if($ADAdmin -is [Hashtable])
    {
        Factory-Read-Hashtable $ADAdmin
    }else
    {
	    Factory-Read-Array $ADAdmin
    }
     
    $Admin+=$global:alldata
    $global:alldata=@()
    
    #Firewall Rule
    
    #$FW_list = az mysql server firewall-rule list -g $ser_rg -s $ser_dom | Out-File $folder\Output\Single\$ServerName\${ServerName}_Single_FW_Rule.json
    $FWList=az mysql server firewall-rule list -g $ser_rg -s $ser_dom| ConvertFrom-Json| ForEach-Object { $_ | Add-Member -MemberType NoteProperty -Name 'Servername' -Value $ServerName -PassThru} | ConvertTo-Json
    $FWList = $FWList|ConvertFrom-Json | ConvertTo-HashTable
    if($FWList -is [Hashtable])
    {
        Factory-Read-Hashtable $FWList
    }else
    {
	    Factory-Read-Array $FWList
    }
    $Firewall+=$global:alldata
    $global:alldata=@()

    #Replica List
    
    $Replica_List=az mysql server replica list -g $ser_rg -s $ser_dom|ConvertFrom-Json| ConvertTo-HashTable
    if($Replica_List -is [Hashtable])
    {
        Factory-Read-Hashtable $Replica_List
    }else
    {
	    Factory-Read-Array $Replica_List
    }
    $Replica+=$global:alldata
    $global:alldata=@()

    #CMK List

    $KeyList=az mysql server key list -g $ser_rg -s $ser_dom | ConvertFrom-Json| ForEach-Object { $_ | Add-Member -MemberType NoteProperty -Name 'Servername' -Value $ServerName -PassThru} | ConvertTo-Json
    $KeyList = $KeyList|ConvertFrom-Json | ConvertTo-HashTable
    if($KeyList -is [Hashtable])
    {
        Factory-Read-Hashtable $KeyList
    }else
    {
            Factory-Read-Array $KeyList
    }
    $CMKey+=$global:alldata
    $global:alldata=@()

    #MSDef List

    $MSDefList=az security pricing show -n 'OpenSourceRelationalDatabases' | ConvertFrom-Json| ForEach-Object { $_ | Add-Member -MemberType NoteProperty -Name 'Servername' -Value $ServerName -PassThru} | ConvertTo-Json
    $MSDefList = $MSDefList|ConvertFrom-Json | ConvertTo-HashTable
    if($MSDefList -is [Hashtable])
    {
        Factory-Read-Hashtable $MSDefList
    }else
    {
            Factory-Read-Array $MSDefList
    }
    $MSDef+=$global:alldata
    $global:alldata=@()

    #Serend List

    $SerEndList=az mysql server vnet-rule list --resource-group $ser_rg  --server-name $ServerName | ConvertFrom-Json| ForEach-Object { $_ | Add-Member -MemberType NoteProperty -Name 'Servername' -Value $ServerName -PassThru} | ConvertTo-Json
    $SerEndList = $SerEndList|ConvertFrom-Json | ConvertTo-HashTable
    if($SerEndList -is [Hashtable])
    {
        Factory-Read-Hashtable $SerEndList
    }else
    {
            Factory-Read-Array $SerEndList
    }
    $SerEnd+=$global:alldata
    $global:alldata=@()

    #Pvtend List

    $PvtEndList=az network private-endpoint-connection list --type Microsoft.DBforMySQL/servers -g $ser_rg -n $ser_dom | ConvertFrom-Json| ForEach-Object { $_ | Add-Member -MemberType NoteProperty -Name 'Servername' -Value $ServerName -PassThru} | ConvertTo-Json
    $PvtEndList = $PvtEndList|ConvertFrom-Json | ConvertTo-HashTable
    if($PvtEndList -is [Hashtable])
    {
        Factory-Read-Hashtable $PvtEndList
    }else
    {
            Factory-Read-Array $PvtEndList
    }
    $PvtEnd+=$global:alldata
    $global:alldata=@()
    
  }
  catch
  {
      throw $_.Exception.Message  
      throw  $_.Exception.Response.StatusCode.Value__
      exitcode
      }
      #Write-Host "info gathering completed successfully for [$ServerName]." -ForegroundColor Green
      }
      else
      {
      Write-Host "MySQL Single server [$ServerName] is in ""$userVisibleState"" state, Database(s) information can't be captured for [$ServerName]." -ForegroundColor Red
      }
      }
    $Serverdata| ForEach-Object {[PSCustomObject]$_}  | Export-CSV -NoTypeInformation -Path $PSScriptRoot\Output\Server_List.csv -Append -Force
    $DBList| ForEach-Object {[PSCustomObject]$_} | Export-CSV -NoTypeInformation -Path $PSScriptRoot\Output\DB_Details.csv -Append -Force
    $ServerConf| ForEach-Object {[PSCustomObject]$_} | Export-CSV -NoTypeInformation -Path $PSScriptRoot\Output\Configuration_Data.csv -Append -Force
    $Admin| ForEach-Object {[PSCustomObject]$_} | Export-CSV -NoTypeInformation -Path $PSScriptRoot\Output\AD_Admin.csv -Append -Force
    $Firewall| ForEach-Object {[PSCustomObject]$_} | Export-CSV -NoTypeInformation -Path $PSScriptRoot\Output\FW_List.csv -Append -Force
    $Replica| ForEach-Object {[PSCustomObject]$_} | Export-CSV -NoTypeInformation -Path $PSScriptRoot\Output\Replica_List.csv -Append -Force
    $CMKey| ForEach-Object {[PSCustomObject]$_} | Export-CSV -NoTypeInformation -Path $PSScriptRoot/Output/CMK_List.csv -Append -Force
    $MSDef| ForEach-Object {[PSCustomObject]$_} | Export-CSV -NoTypeInformation -Path $PSScriptRoot/Output/MSDef_List.csv -Append -Force
    $SerEnd| ForEach-Object {[PSCustomObject]$_} | Export-CSV -NoTypeInformation -Path $PSScriptRoot/Output/SerEnd_List.csv -Append -Force
    $PvtEnd| ForEach-Object {[PSCustomObject]$_} | Export-CSV -NoTypeInformation -Path $PSScriptRoot/Output/PvtEnd_List.csv -Append -Force
    if($Outfiledata -ne $null){
    $Outfiledata | select Host_Name,Resource_Group,Port,VCore,User_ID,Password,Auth_Type,DB_Name,Tenant,Subscription_ID,Approval_Status,SSL_Mode | Export-CSV -NoTypeInformation $PSScriptRoot\Factory_MySQL_Server_Input_file.csv
    }
    }
    
    Write-Host "`n=============================================================================================================="  
    Write-Host "Information gathered ==> $folder\Output\ " -ForegroundColor Green -BackgroundColor Black
    Write-Host "MySQL Server List created ==> $PSScriptRoot\Factory_MySQL_Server_Input_file.csv " -ForegroundColor Green -BackgroundColor Black
    Write-Host "Update mandatory fields along with ""Approval_Status"" column in above CSV and execute script ""Factory-MySQL-Windows.ps1"" to gather database level info." -ForegroundColor Yellow -BackgroundColor Black
    Write-Host "==============================================================================================================" 
      

$filenames = 'AD_Admin.csv', 'Configuration_Data.csv', 'DB_Details.csv', 'FW_List.csv','Replica_List.csv','Server_List.csv','Single_Server_List.json'
foreach ($filename in $filenames) {
$found=$false; 
Get-ChildItem -Path $PSScriptRoot\Output\ -Recurse | ForEach-Object {if($filename -eq $_.Name) {$found=$true;CONTINUE}$found=$false;}-End { if($found -ne $true) { Write-Host 'FILE ' $filename ' missing in the folder.' -foregroundcolor red}
 }
 }
 If(-Not(Test-Path $PSScriptRoot\Factory_MySQL_Server_Input_file.csv))
 {
 Write-Host 'FILE ' Factory_MySQL_Server_Input_file.csv ' missing in the folder.' -foregroundcolor red
 }

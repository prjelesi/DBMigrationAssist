#---------------------------------------------------------------------------------------------------------------------------*
#  Purpose        : Script for Information gathering of Azure PostgreSQL Flexi Server
#  Schedule       : Ad-Hoc / On-Demand
#  Date           : 25-Nov-2024
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
# Powershell.exe -File .\Factory-PostgreSQL-CLI-Windows.ps1
#
<#
    Change Log
    ----------
•	Customer consent to install Azure CLI
•	Excluded Flexi server Azure CLI commands.
•	Excluded Azure CLI commands Json file generation for single servers except Server list.
•	Incorporated Vcore column in INPUT CSV  Sheet  Factory_PostgreSQL_Server_Input_file.xlsx file (Server_List Worksheet)
•	Incorporated servername in DB_List, Config_Details,AD Admin and Firewall-rule List  CLI commands output in output.xlsx
•	No column Filter applied when exporting AZURE CLI Commands output to output.xlsx file
•	Included az postgres server replica list CLI
•	Script now can be run directly without wrapper.
•	Output files creation verification added at end of script.
•	-NoTypeInformation to suppress the first line from CSVs.        
•	Skip execution for servers where server state is not "Ready" to suppress error message and to gain performace.
•	Progress bar addition with server in progress
•	Included Multi-subscription support        
#>
Set-ExecutionPolicy Bypass -Scope currentuser
CLS


#---------------------------------------------------------PROGRAM BEGINS HERE----------------------------------------------------------

write-host "                                                                            " -BackgroundColor DarkMagenta
Write-Host "     Welcome to Factory - PostgreSQL_Info_Gathering_Automation                  " -ForegroundColor white -BackgroundColor DarkMagenta
write-host "                     (OSS DB Migration Factory)                             " -BackgroundColor DarkMagenta
write-host "                                                                            " -BackgroundColor DarkMagenta
Write-Host " "

$folder = $PSScriptRoot
$postgrespath = where.exe psql
$today_date=Get-Date -Format "MM_dd_yyyy_HH_mm"
 Write-Host "=============================================================================================================="  
 Start-Transcript -path  $folder\Logs\Factory-PostgreSQL_Info_Gathering_Automation_Transcript_$today_date.txt  -Append
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
        $cfolder=New-Item $newFolder -ItemType Directory
        Write-Host "-$newFolder folder created..."
    }
}

if ($postgrespath -like "*\psql*") {
	Write-Host "PostgreSQL exists. Continuing execution..." -ForegroundColor Green
}
else {
	Write-Host "PostgreSQL is not installed or its path is not in the environment variables. Please install PostgreSQL, add its path to the environment variables, and rerun the script." -BackgroundColor Red
	exit
}


createFolder $folder\Downloads\
createFolder $folder\Logs\
createFolder $folder\Output\
createFolder $folder\Output\Flexi\

# Read the input config CSV and validate
$inputfile = $folder+"\Azure_Subscription.csv"
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
         Write-Host "Please see the error below & Azure PostgreSQL Info-Gathering has been stopped          "  
         throw $_.Exception.Message
         exitcode
        }

}    
 
 $ColumnList=$ConfigList | Get-Member -MemberType NoteProperty | %{"$($_.Name)"}
     if (($ColumnList.Contains("Tenant")) -and
        ($ColumnList.Contains("Subscription_ID"))){

        Write-Host "CSV validation is done successfully " 
        }
     else {Write-Host "There are mismatches in the CSV column . Kindly check and retrigger the automation "  -BackgroundColor Red
           exitCode}


Unblock-File $folder/Validation_Scripts/Check_PowerShell_Version.ps1
Unblock-File $folder/Validation_Scripts/azurecli.ps1
      
# Check PowerShell version
$Validation=@()
$Outfiledata=@()
$global:alldata =@()
$global:row=@{}
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
    $ha = @()
    $samezoneha = @()
    $zoneredundantha = @()
    $georedundantbck = @()
    $resiliency = @()


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
     
    #Server list fetch for Flexi Server
    $Flexi_list_Out = az postgres flexible-server list | Out-File $folder\Output\Flexi\Flexi_Server_List.json -Append
    $Flexi_list_Out = az postgres flexible-server list | Out-File $folder\Factory_PostgreSQL_Server_Input_file.csv -Append
    
    $ser_details = az postgres flexible-server list|ConvertFrom-Json
         
    $ser_list = az postgres flexible-server list |ConvertFrom-Json | ConvertTo-HashTable
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
    Write-Host "There is no PostgreSQL Flexible server on Subscription [$Subscription] for Tenant [$tenant]" -ForegroundColor Red
    Write-host "Please check Subscription on input file: Azure_Subscription.csv" -ForegroundColor Red
    #Write-Host "=============================================================================================================="  
   # exitCode
    }
  foreach ($i in $ser_details)
  {
  

      #Updating input file with server details
      $ServerName= $i.name
      $Flexi_User_Name = $i.administratorLogin
      $ser_rg = $i.resourceGroup  
      $domain_name = $i.fullyQualifiedDomainName
      $dom = $domain_name.Split(".")
      $ser_dom = $dom[0]
	  $Logon_User=$Flexi_User_Name
      $vcore=$i.sku.name
      $tier=$i.sku.tier
      $userVisibleState=$i.state 
       $per_complete=[math]::round($k/$count*100)
      Write-Progress -Activity "Server:$ServerName is in Progress..." -Status "$per_complete% Complete:" -PercentComplete $per_complete
      $k++
      $Outfiledata+=New-Object psobject -Property @{Host_Name=$domain_name;Resource_Group=$ser_rg;Port="5432";VCore=$vcore;tier=$tier;Auth_Type="PostgreSQL";User_ID=$Logon_User;Password="";DB_Name="postgres";Tenant=$tenant;Subscription_ID=$Subscription;Approval_Status="No";SSL_Mode="prefer"}
 if ($userVisibleState -match "Ready")
{           
    try
    {    
    $dbdata = az postgres flexible-server db list -g $ser_rg -s $ser_dom | ConvertFrom-Json | ForEach-Object { $_ | Add-Member -MemberType NoteProperty -Name 'Servername' -Value $ServerName -PassThru} | ConvertTo-Json
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
    
   
    $FWList=az postgres flexible-server firewall-rule list -g $ser_rg -n $ser_dom| ConvertFrom-Json| ForEach-Object { $_ | Add-Member -MemberType NoteProperty -Name 'Servername' -Value $ServerName -PassThru} | ConvertTo-Json
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
    
    $Replica_List=az postgres flexible-server replica list -g $ser_rg -n $ser_dom|ConvertFrom-Json| ConvertTo-HashTable
    if($Replica_List -is [Hashtable])
    {
        Factory-Read-Hashtable $Replica_List
    }else
    {
	    Factory-Read-Array $Replica_List
    }
   
    $Replica+=$global:alldata
    
    $global:alldata=@()
     
    #MSDef List

    $MSDefList=az security pricing show -n 'OpenSourceRelationalDatabases'| ConvertFrom-Json| ForEach-Object { $_ | Add-Member -MemberType NoteProperty -Name 'Servername' -Value $ServerName -PassThru} | ConvertTo-Json
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
  }
  catch
  {
      throw $_.Exception.Message  
      throw $_.Exception.Response.StatusCode.Value__
      exitcode
    }
    }
     else
     {
      Write-Host "PostgreSQL Flexi server [$ServerName] is in ""$userVisibleState"" state, Database(s) information can't be captured for [$ServerName]." -ForegroundColor Red
      }
      }
	  
    $Serverdata| ForEach-Object {[PSCustomObject]$_}  | Export-CSV -NoTypeInformation -Path $PSScriptRoot\Output\Flexi\Flexi_Server_List.csv -Append -Force
    $DBList| ForEach-Object {[PSCustomObject]$_} | Export-CSV -NoTypeInformation -Path $PSScriptRoot\Output\Flexi\Flexi_DB_Details.csv -Append -Force
    $Firewall| ForEach-Object {[PSCustomObject]$_} | Export-CSV -NoTypeInformation -Path $PSScriptRoot\Output\Flexi\Flexi_FW_List.csv -Append -Force
    $Replica| ForEach-Object {[PSCustomObject]$_} | Export-CSV -NoTypeInformation -Path $PSScriptRoot\Output\Flexi\Flexi_Replica_List.csv -Append -Force
    $MSDef| ForEach-Object {[PSCustomObject]$_} | Export-CSV -NoTypeInformation -Path $PSScriptRoot\Output\Flexi\Flexi_MSDef_List.csv -Append -Force
     
     if($Outfiledata -ne $null){
    $Outfiledata | select Host_Name,Resource_Group,Port,VCore,tier,Auth_Type,User_ID,Password,DB_Name,tenant,Subscription_ID,Approval_Status,SSL_Mode | Export-Csv -NoTypeInformation $PSScriptRoot\Output\Flexi\Factory_PostgreSQL_Flexi_Server_Input_file.csv
    $Outfiledata | select Host_Name,Resource_Group,Port,VCore,Auth_Type,User_ID,Password,DB_Name,tenant,Subscription_ID,Approval_Status,SSL_Mode | Export-Csv -NoTypeInformation $PSScriptRoot\Factory_PostgreSQL_Server_Input_file.csv  -Force
    }
    }
    Write-Host "=============================================================================================================="  
    Write-Host "Information gathered ==> $folder\Output\ " -ForegroundColor Green -BackgroundColor Black
    Write-Host "PostgreSQL Server List created ==> $PSScriptRoot\Factory_PostgreSQL_Server_Input_file.csv" -ForegroundColor Green -BackgroundColor Black
    Write-Host "For Version upgrade, Update mandatory fields along with ""Approval_Status"" column in above CSV and execute script ""Factory-PostgreSQL-Flexi-Windows.ps1"" to gather database level info." -ForegroundColor Yellow -BackgroundColor Black
    Write-Host "==============================================================================================================" 
  
   
$filenames =  'Flexi_DB_Details.csv', 'Flexi_FW_List.csv','Flexi_Replica_List.csv','Flexi_Server_List.csv','Flexi_Server_List.json'
foreach ($filename in $filenames) {
$found=$false; 
Get-ChildItem -Path $PSScriptRoot\Output\ -Recurse | ForEach-Object {if($filename -eq $_.Name) {$found=$true;CONTINUE}$found=$false;}-End { if($found -ne $true) { Write-Host 'FILE ' $filename ' missing in the folder.' -foregroundcolor red}
 }
 }
 If(-Not(Test-Path $PSScriptRoot\Output\Flexi\Factory_PostgreSQL_Flexi_Server_Input_file.csv))
 {
 Write-Host 'FILE ' Factory_PostgreSQL_Flexi_Server_Input_file.csv ' missing in the folder.' -foregroundcolor red
 }

exitcode



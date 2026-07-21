$Module_Name=$args[0]
$Installed_Modules=Get-InstalledModule
if($Installed_Modules.Name.contains($Module_Name)){
$status="SUCCESS"
$comments="$Module_Name Module Already Exists."
}else{
try{
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned
Install-Module -Name $Module_Name -Force
$Installed_Modules=Get-InstalledModule
if($Installed_Modules.Name.contains($Module_Name)){
$status="SUCCESS"
$comments="$Module_Name Module Already Exists."
}else{
$status="FAILED"
$comments="Failed to install Module $Module_Name. Please install Manually"

}
}catch{

$status="FAILED"
$comments="Failed to install Module $Module_Name. Please install Manually"

}

}

$Output = New-Object psobject -Property @{Validation_Type="Check Powershell Module :: $Module_Name";Status =$status;Comments=$comments}
return $Output
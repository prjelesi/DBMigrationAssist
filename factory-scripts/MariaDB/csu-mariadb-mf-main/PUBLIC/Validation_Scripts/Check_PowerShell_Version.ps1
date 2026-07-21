function PowerShell_Version()
{
    try
    {
        $ps_version = $PSVersionTable.PSVersion
        if ($ps_version -ge "5.1”)
        {
            $status="SUCCESS"
            $comments="Powershell version is $ps_version."
        }
        else
        {
            $status="FAILED"
            $comments="Powershell version is $ps_version. Please Install PowerShell Version above 5 manually and rerun the script."
        }
    }
    catch
    {
        $status="FAILED"
        $comments="Unable to fetch Powershell Version. Please check it manually."
    }
    $Output = New-Object psobject -Property @{Validation_Type="Check PoweShell Version";Status=$status;Comments=$comments}
    return $Output
}
PowerShell_Version
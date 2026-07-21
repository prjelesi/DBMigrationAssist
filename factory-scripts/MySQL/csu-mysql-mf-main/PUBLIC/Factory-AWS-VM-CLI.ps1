#  Schedule       : Ad-Hoc / On-Demand
#  Date           : 28-FEB-2025
#  Author         : Rackimuthu Kandaswamy , ArunKumar, Mukesh
#  Version        : 0.1
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
Set-ExecutionPolicy Bypass -Scope currentuser
CLS

#---------------------------------------------------------PROGRAM BEGINS HERE----------------------------------------------------------

write-host "                                                                            " -BackgroundColor DarkMagenta
Write-Host "     Welcome to AWS EC2 Information Gathering Automation                  " -ForegroundColor white -BackgroundColor DarkMagenta
write-host "                                                                            " -BackgroundColor DarkMagenta
Write-Host " "

$folder = $PSScriptRoot
$today_date = Get-Date -Format "MM_dd_yyyy_HH_mm"
Write-Host "=============================================================================================================="  
Start-Transcript -path  "$folder\Logs\AWS_RDS_Info_Gathering_Automation_Transcript_$today_date.txt" -Append
Write-Host "=============================================================================================================="  

function exitCode {
    Write-Host "-Ending Execution"
    Stop-Transcript
    exit
}

function createFolder([string]$newFolder) {
    if (Test-Path $newFolder) {
        Write-Host "-Folder '$newFolder' Exist..."
    } else {
        New-Item $newFolder -ItemType Directory | Out-Null
        Write-Host "-$newFolder folder created..."
    }
}

createFolder "$folder\Logs"
createFolder "$folder\Output"

Unblock-File $folder/Validation_Scripts/Check_PowerShell_Version.ps1
Unblock-File $folder/Validation_Scripts/awscli.ps1

# Check PowerShell version
$Validation=@()
$Outfiledata=@()
$global:alldata =@()
$global:row=@{}
$Validation+=& "$folder/Validation_Scripts/Check_PowerShell_Version.ps1"
$Validation+=& "$folder/Validation_Scripts/awscli.ps1"

 Write-Host "=============================================================================================================="  
 Write-Host "Below are the Validation Results"  -ForegroundColor Green  
 Write-Host "=============================================================================================================="  
Write-Host ($Validation | select Validation_Type,Status,Comments | Format-Table | Out-String)

If($Validation.Status.Contains("FAILED"))
{
 Write-Host "There are errors during validation . Terminating the execution ."  -ForegroundColor Red
 exitcode  
}


try {
    # Define AWS Subscription CSV file path
    $awsSubscriptionFile = "$folder\AWS_Subscription.csv"
    
    # Check if the AWS Subscription file exists
    if (-not (Test-Path -Path $awsSubscriptionFile -PathType Leaf)) {
        Write-Host "Unable to read the AWS Subscription file [$awsSubscriptionFile]. Check file & its permission..." -BackgroundColor Red
        exit
    }

    # Import AWS credentials from CSV
    $awsCredentials = Import-CSV -Path $awsSubscriptionFile

    # Loop through each row in the CSV file and process them individually
    foreach ($credentials in $awsCredentials) {
        $awsAccessKey = $credentials.AWSAccessKeyID
        $awsSecretKey = $credentials.AWSSecretAccessKey
        $awsRegion = $credentials.Region
        $awsOutputFormat = $credentials.DefaultOutputFormat
        $awsSessionToken = $credentials.SessionToken  # Capture the session token (optional)

        Write-Host "Processing AWS Account with Access Key: $awsAccessKey and Region: $awsRegion..." -ForegroundColor Cyan

        # Set environment variables for AWS credentials
        $Env:AWS_ACCESS_KEY_ID = $awsAccessKey
        $Env:AWS_SECRET_ACCESS_KEY = $awsSecretKey
        if ($awsSessionToken) {
            $Env:AWS_SESSION_TOKEN = $awsSessionToken
        }

        # Optional: Update the AWS credentials file for AWS CLI (if needed)
        $awsCredentialsFile = [System.IO.Path]::Combine($env:USERPROFILE, ".aws", "credentials")
        
        # Create AWS credentials file directory if it doesn't exist
        If (-not (Test-Path -Path (Split-Path -Path $awsCredentialsFile))) {
            New-Item -Path (Split-Path -Path $awsCredentialsFile) -ItemType Directory -Force
        }

        # Correctly format the credentials content for the profile
        $profileSection = "[default]"  # Change this if you're using a specific profile name

        # Add credentials content (Make sure there are no extra spaces or lines)
        $credentialsContent = @"
$profileSection
aws_access_key_id=$awsAccessKey
aws_secret_access_key=$awsSecretKey
aws_session_token=$awsSessionToken  # Only add this if the SessionToken exists
"@

        # Overwrite the credentials file (avoid appending multiple times)
        $credentialsContent | Set-Content -Path $awsCredentialsFile -Force

        # Check if AWS credentials, region, or session token are set
        if (-not $awsAccessKey -or -not $awsSecretKey -or -not $awsRegion) {
            Write-Host "AWS credentials or region are not set for this row. Skipping this entry..." -ForegroundColor Yellow
            continue
        }

        # Ensure the region is valid and correctly formatted (Remove AZ suffix if present)
        $awsRegion = $awsRegion -replace 'a$|b$|c$', '' # Remove any "a", "b", or "c" suffix (e.g., ap-southeast-2a becomes ap-southeast-2)

        if ($awsRegion -match '[^a-zA-Z0-9-]') {
            Write-Host "Region '$awsRegion' contains invalid characters. Skipping this entry..." -ForegroundColor Red
            continue
        }

        # Test the credentials and region by executing a simple AWS CLI command (e.g., describing EC2 instances)
        Write-Host "Testing AWS credentials with a simple AWS CLI command..." -ForegroundColor Green
        $testCommand = aws ec2 describe-instances --region $awsRegion --query "Reservations[].Instances[].InstanceId" --output text 2>&1
        $stat = $LASTEXITCODE

        if ($stat -ne 0) {
            Write-Host "Failed to authenticate with AWS using the provided credentials for region $awsRegion." -ForegroundColor Red
            Write-Host "Error details: $testCommand" -ForegroundColor Red
            Write-Host "Please check your AWS Access Key, Secret Key, or Region." -BackgroundColor Red
            continue
        } else {
            Write-Host "Successfully authenticated with AWS for region $awsRegion. Proceeding with automation..." -ForegroundColor Green
        }

        # Set AWS credentials for the session explicitly, handle optional SessionToken
        if ($awsSessionToken) {
            Set-AWSCredential -AccessKey $awsAccessKey -SecretKey $awsSecretKey -SessionToken $awsSessionToken -StoreAs default
        } else {
            Set-AWSCredential -AccessKey $awsAccessKey -SecretKey $awsSecretKey -StoreAs default
        }

        Set-DefaultAWSRegion -Region $awsRegion

        # Get the list of EC2 instances
        $instances = aws ec2 describe-instances --region $awsRegion --query "Reservations[].Instances[].InstanceId" --output text

        if (-not $instances) {
            Write-Host "Failed to retrieve EC2 instances for region $awsRegion. Skipping..." -ForegroundColor Red
            continue
        }

        foreach ($instance in $instances -split "`n") {
            Write-Host "Processing EC2 Instance: $instance"

            # Fetch the metadata for the EC2 instance
            $instanceMetadata = aws ec2 describe-instances --instance-ids "$instance" --region $awsRegion --query "Reservations[].Instances[].{
                ServerName: Tags[?Key=='Name'].Value | [0],
                InstanceId: InstanceId,
                InstanceType: InstanceType,
                State: State.Name,
                PublicIpAddress: PublicIpAddress,
                PrivateIpAddress: PrivateIpAddress,
                PrivateDnsName: PrivateDnsName,
                PublicDnsName: PublicDnsName,
                LaunchTime: LaunchTime,
                AvailabilityZone: Placement.AvailabilityZone,
                SecurityGroups: SecurityGroups[].GroupName,
                Tags: Tags,
                BlockDeviceMappings: BlockDeviceMappings[].DeviceName,
                VolumeIds: BlockDeviceMappings[?Ebs.VolumeId].Ebs.VolumeId,
                VolumeSize: BlockDeviceMappings[?Ebs.VolumeSize].Ebs.VolumeSize,
                VolumeTypes: BlockDeviceMappings[?Ebs.VolumeType].Ebs.VolumeType,
                VolumeIops: BlockDeviceMappings[?Ebs.Iops].Ebs.Iops,
                MultiAttachEnabled: BlockDeviceMappings[?Ebs.MultiAttachEnabled].Ebs.MultiAttachEnabled
            }" --output json | ConvertFrom-Json

            if (-not $instanceMetadata) {
                Write-Host "Failed to retrieve metadata for EC2 instance: $instance." -ForegroundColor Red
                continue
            }

            # Debugging: Output instance metadata to console for review
            Write-Host "Instance Metadata: $($instanceMetadata | ConvertTo-Json -Depth 3)"



            # Set the output folder path
            $OutputFolder = "$folder\Output"
            $combinedCsv = "$OutputFolder\AWS_EC2_Instances_Metadata.csv"

            # Ensure output folder exists
            If (-Not (Test-Path -Path $OutputFolder)) {
                New-Item -Path $OutputFolder -ItemType Directory
                Write-Host "Output folder created at: $OutputFolder"
            }

            # Export instance metadata to CSV
            try {


                    # Fetch CloudWatch CPU Utilization Metrics for the instance

                    $cpu = @()
                    $startTime = (Get-Date).AddHours(-1).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
                    $endTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            

                    $cpuUtilization += aws cloudwatch get-metric-statistics `
                        --namespace AWS/EC2 `
                        --metric-name CPUUtilization `
                        --dimensions Name=InstanceId,Value=$instance `
                        --statistics Average `
                        --period 3600 `
                        --start-time $startTime `
                        --end-time $endTime `
                        --region $awsRegion  --output json | ConvertFrom-Json

                        # Extract CPU Utilization Data
    $cpuData = if ($cpuUtilization.Datapoints) {
        $cpuUtilization.Datapoints | Sort-Object Timestamp | Select-Object -Last 1
    } else {
        $null
    }

    if ($cpuData) {
        Write-Host ("CPU Utilization Data for Instance " + $instance + ":")
        Write-Host "Timestamp: $($cpuData.Timestamp), Average CPUUtilization: $($cpuData.Average)%, Unit: $($cpuData.Unit)"
    } else {
        Write-Host "No CPU Utilization data found for Instance $instance." -ForegroundColor Red
    }


                $instanceMetadata | ForEach-Object {
                    $_ | Select-Object ServerName, 
                                      InstanceId, 
                                      InstanceType, 
                                      State, 
                                      PublicIpAddress, 
                                      PrivateIpAddress, 
                                      PrivateDnsName, 
                                      PublicDnsName, 
                                      LaunchTime, 
                                      AvailabilityZone,
                                      @{Name="SecurityGroups"; Expression={($_.SecurityGroups -join ", ")}},
                                      @{Name="Tags"; Expression={($_.Tags | ForEach-Object { "$($_.Key): $($_.Value)" }) -join ", "}},
                                      @{Name="BlockDeviceMappings"; Expression={($_.BlockDeviceMappings -join ", ")}},
                                      @{Name="VolumeIds"; Expression={($_.VolumeIds -join ", ")}},
                                      @{Name="VolumeSizes"; Expression={($_.VolumeSizes | ForEach-Object { if ($_.VolumeSize) { $_.VolumeSize } else { 'N/A' } }) -join ", "}},
                                      @{Name="VolumeTypes"; Expression={($_.VolumeTypes | ForEach-Object { if ($_.VolumeTypes) { $_.VolumeTypes } else { 'N/A' } }) -join ", "}},
                                      @{Name="VolumeIops"; Expression={($_.VolumeIops | ForEach-Object { if ($_.VolumeIops) { $_.VolumeIops } else { 'N/A' } }) -join ", "}},
                                      @{Name="MultiAttachEnabled"; Expression={($_.MultiAttachEnabled | ForEach-Object { if ($_.MultiAttachEnabled) { $_.MultiAttachEnabled } else { 'N/A' } }) -join ", "}},
                                      @{Name="CPUUtilization"; Expression={if ($cpuData) { "$($cpuData.Average)%" } else { "No Data" }}},
                                      @{Name="CPUUtilizationTimestamp"; Expression={if ($cpuData) { "$($cpuData.Timestamp)" } else { "No Data" }}},
                                      @{Name="CPUUtilizationUnit"; Expression={if ($cpuData) { "$($cpuData.Unit)" } else { "No Data" }}}


                } | Export-Csv -NoTypeInformation -Path $combinedCsv -Force

                # Confirm the CSV was created
                If (Test-Path -Path $combinedCsv) {
                    Write-Host "CSV file created at: $combinedCsv"
                } else {
                    Write-Host "Failed to create CSV file." -ForegroundColor Red
                }
            } catch {
                Write-Host "Error exporting CSV: $_" -ForegroundColor Red
            }



            Write-Host "Instance metadata has been successfully saved to $combinedCsv"
            Write-Host "=============================================================================================================="
            Write-Host "All EC2 instance data has been gathered and saved to the Output folder." -ForegroundColor Green
            Write-Host "=============================================================================================================="


            
             
       
           }

        # Check if the expected CSV file exists in the folder
        If (-Not (Test-Path -Path $combinedCsv)) {
            Write-Host "FILE $combinedCsv is missing in the folder." -ForegroundColor Red
        } else {
            Write-Host "File $combinedCsv exists." -ForegroundColor Green
        }

        Write-Host "Information gathering completed successfully." -ForegroundColor Green
    }
} catch {
    # Catch any errors and output them
    Write-Host "Information gathering for AWS EC2 completed with errors." -ForegroundColor Red
}


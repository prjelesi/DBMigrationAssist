# Schedule       : Ad-Hoc / On-Demand
# Date           : 28-FEB-2025
# Author         : Rackimuthu Kandaswamy,Sharad, ArunKumar, Mukesh
# Version        : 0.2 (Cross-Platform)

# INPUT          : NONE
# VARIABLE       : NONE
# PARENT         : NONE
# CHILD          : NONE

# ---------------------------------------------
# IMPORTANT NOTE : For Non-Production use only!
# ---------------------------------------------

# --------------------------------------------------- SETUP ------------------------------------------------------------


Set-ExecutionPolicy Bypass -Scope currentuser
CLS

#---------------------------------------------------------PROGRAM BEGINS HERE----------------------------------------------------------

write-host "                                                                            " -BackgroundColor DarkMagenta
Write-Host "     Welcome to AWS RDS Information Gathering Automation                    " -ForegroundColor white -BackgroundColor DarkMagenta
write-host "                                                                            " -BackgroundColor DarkMagenta
Write-Host " "



# Cross-platform AWS RDS Info Gathering Script

# Detect Windows and Linux environments more reliably
$IsWindowsEnv = $PSVersionTable.OS -like "*Windows*" -or $env:OS -eq "Windows_NT"
$IsLinuxEnv = (Test-Path "/etc/os-release") -or ($PSVersionTable.Platform -eq 'Unix')
$folder = $PSScriptRoot
$today_date = Get-Date -Format "MM_dd_yyyy_HH_mm"
$logPath = Join-Path -Path $folder -ChildPath "Logs"
$logFile = Join-Path -Path $logPath -ChildPath "AWS_RDS_Info_Gathering_Automation_Transcript_$today_date.txt"
$outputPath = Join-Path -Path $folder -ChildPath "Output"

Write-Host "=============================================================================================================="
Start-Transcript -Path $logFile -Append
Write-Host "=============================================================================================================="

function exitCode {
    Write-Host "-Ending Execution"
    Stop-Transcript
    exit
}

function createFolder([string]$newFolder) {
    if (-not (Test-Path $newFolder)) {
        New-Item -Path $newFolder -ItemType Directory | Out-Null
        Write-Host "-$newFolder folder created..."
    } else {
        Write-Host "-Folder '$newFolder' exists..."
    }
}

function Check-AwsCli {
    $awsExists = Get-Command aws -ErrorAction SilentlyContinue

    if (-not $awsExists) {
        Write-Host "`nAWS CLI not found!" -ForegroundColor Red

        if ($IsWindowsEnv) {
            # Windows installation logic
            $installerUrl = "https://awscli.amazonaws.com/AWSCLIV2.msi"
            $installerPath = "$env:TEMP\AWSCLIV2.msi"

            Write-Host "Downloading AWS CLI installer..."
            Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -ErrorAction Stop

            Write-Host "Installing AWS CLI..."
            $process = Start-Process msiexec.exe -ArgumentList "/i `"$installerPath`" /quiet /norestart" -Wait -PassThru
            Remove-Item -Path $installerPath -ErrorAction SilentlyContinue

            Start-Sleep -Seconds 5
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::Machine)
            $awsExists = Get-Command aws -ErrorAction SilentlyContinue
        } elseif ($IsLinuxEnv) {
            # Linux installation logic
            $existingAwsPath = "/usr/local/aws-cli/v2/current/bin/aws"
            if (Test-Path $existingAwsPath) {
                Write-Host "AWS CLI already installed at $existingAwsPath" -ForegroundColor Green
                
                # Check if the AWS CLI binary is in the system PATH
                $awsInPath = $env:PATH -split ":" | Where-Object { $_ -eq "/usr/local/aws-cli/v2/current/bin" }
                if ($awsInPath) {
                    Write-Host "AWS CLI is in the PATH." -ForegroundColor Green
                } else {
                    Write-Host "Adding AWS CLI to the PATH..." -ForegroundColor Yellow
                    $env:PATH += ":/usr/local/aws-cli/v2/current/bin"
                }
                
                # Now check if the aws command works
                $awsExists = Get-Command aws -ErrorAction SilentlyContinue
            } else {
                Write-Host "AWS CLI not found in the expected path, attempting to install..." -ForegroundColor Yellow
                
                # Set up download path and installer path
                $tempDir = "/tmp/awscliv2"
                $zipPath = "$tempDir/awscliv2.zip"
                $installDir = "$tempDir/aws"

                # Create temp directory if it doesn't exist
                if (-not (Test-Path $tempDir)) {
                    New-Item -ItemType Directory -Path $tempDir | Out-Null
                }

                # Download the AWS CLI zip file
                Invoke-WebRequest -Uri "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -OutFile $zipPath -ErrorAction Stop

                # Extract the downloaded zip
                Expand-Archive -Path $zipPath -DestinationPath $tempDir -Force

                # Run the installer
                $installCommand = "$installDir/install"
                sudo $installCommand

                # Clean up
                Remove-Item -Recurse -Force $tempDir

                # Check if the installation was successful
                $awsExists = Get-Command aws -ErrorAction SilentlyContinue
            }
        } else {
            Write-Host "Unsupported OS detected. Manual AWS CLI installation required." -ForegroundColor Red
            throw "Unsupported OS. Please install AWS CLI manually."
        }

        if (-not $awsExists) {
            throw "AWS CLI installation failed or not available in PATH."
        }
    }

    Write-Host "AWS CLI is available." -ForegroundColor Green
}

# Call the Check-AwsCli function
Check-AwsCli

createFolder $logPath
createFolder $outputPath

# Unblock validation scripts if on Windows
if ($IsWindows) {
    Unblock-File (Join-Path $folder "Validation_Scripts/Check_PowerShell_Version.ps1")
}

# Run validation
$Validation = @()
$Validation += & (Join-Path $folder "Validation_Scripts/Check_PowerShell_Version.ps1")
$Validation += & (Join-Path $folder "Validation_Scripts/awscli.ps1")

Write-Host "=============================================================================================================="
Write-Host "Below are the Validation Results" -ForegroundColor Green
Write-Host "=============================================================================================================="
Write-Host ($Validation | Select-Object Validation_Type, Status, Comments | Format-Table | Out-String)

if ($Validation.Status.Contains("FAILED")) {
    Write-Host "There are errors during validation. Terminating the execution." -ForegroundColor Red
    exitCode
}

try {
    $awsSubscriptionFile = Join-Path -Path $folder -ChildPath "AWS_Subscription.csv"
    
    if (-not (Test-Path $awsSubscriptionFile)) {
        Write-Host "Unable to read the AWS Subscription file [$awsSubscriptionFile]. Check file & its permission..." -ForegroundColor Red
        exit
    }

    $awsCredentials = Import-Csv -Path $awsSubscriptionFile

    foreach ($credentials in $awsCredentials) {
        $awsAccessKey = $credentials.AWSAccessKeyID
        $awsSecretKey = $credentials.AWSSecretAccessKey
        $awsRegion = $credentials.Region
        $awsOutputFormat = $credentials.DefaultOutputFormat
        $awsSessionToken = $credentials.SessionToken

        Write-Host "Processing AWS Account with Access Key: $awsAccessKey and Region: $awsRegion..." -ForegroundColor Cyan

        # Set environment variables
        $Env:AWS_ACCESS_KEY_ID = $awsAccessKey
        $Env:AWS_SECRET_ACCESS_KEY = $awsSecretKey
        if ($awsSessionToken) {
            $Env:AWS_SESSION_TOKEN = $awsSessionToken
        }

        # Write credentials to file
        $awsCredentialsFile = Join-Path -Path $HOME -ChildPath ".aws/credentials"
        $awsDir = Split-Path $awsCredentialsFile -Parent
        if (-not (Test-Path $awsDir)) {
            New-Item -Path $awsDir -ItemType Directory -Force | Out-Null
        }

        $profileSection = "[default]"
        $credentialsContent = @"
$profileSection
aws_access_key_id=$awsAccessKey
aws_secret_access_key=$awsSecretKey
aws_session_token=$awsSessionToken
"@

        $credentialsContent | Set-Content -Path $awsCredentialsFile -Force

        if (-not $awsAccessKey -or -not $awsSecretKey -or -not $awsRegion) {
            Write-Host "Missing credentials. Skipping..." -ForegroundColor Yellow
            continue
        }

        $awsRegion = $awsRegion -replace 'a$', ''
        if ($awsRegion -match '[^a-zA-Z0-9-]') {
            Write-Host "Region '$awsRegion' contains invalid characters. Skipping..." -ForegroundColor Red
            continue
        }

        Write-Host "Testing AWS CLI..." -ForegroundColor Green
        $testCommand = aws s3 ls --region $awsRegion 2>&1
        $stat = $LASTEXITCODE

        if ($stat -ne 0) {
            Write-Host "Failed to authenticate for region $awsRegion." -ForegroundColor Red
            Write-Host "Details: $testCommand" -ForegroundColor Red
              Write-Host "Please check your AWS Access Key, Secret Key, or Region." -BackgroundColor Red
            continue
        } else {
            Write-Host "Successfully authenticated with AWS for region $awsRegion. Proceeding with automation..." -ForegroundColor Green
        }

        # Fetch RDS Instances
        $instances = aws rds describe-db-instances --region $awsRegion --query "DBInstances[].DBInstanceIdentifier" --output text

        if (-not $instances) {
            Write-Host "No RDS instances found for region $awsRegion." -ForegroundColor Yellow
            continue
        }

        foreach ($instance in $instances -split "`n") {
            Write-Host "Processing RDS Instance: $instance"

            # Fetch the metadata for the RDS instance
            $instanceMetadata = aws rds describe-db-instances --db-instance-identifier "$instance" --region $awsRegion --query "DBInstances[].{
                ID: DBInstanceIdentifier,
                DBInstanceClass: DBInstanceClass,
                Engine: Engine,
                DBInstanceStatus: DBInstanceStatus,
                AllocatedStorage: AllocatedStorage,
                Endpoint: Endpoint.Address,
                InstanceCreateTime: InstanceCreateTime,
                AvailabilityZone: AvailabilityZone,
                MultiAZ: MultiAZ,
                StorageType: StorageType,
                EngineVersion: EngineVersion,
                AutoMinorVersionUpgrade: AutoMinorVersionUpgrade,
                ReadReplicaSourceDBInstanceIdentifier: ReadReplicaSourceDBInstanceIdentifier,
                ReadReplicaDBInstanceIdentifiers: ReadReplicaDBInstanceIdentifiers,
                LicenseModel: LicenseModel,
                Iops: Iops,
                OptionGroupMemberships: OptionGroupMemberships[].OptionGroupName,
                PubliclyAccessible: PubliclyAccessible
            }" --output json | ConvertFrom-Json

            if (-not $instanceMetadata) {
                Write-Host "Failed to retrieve metadata for RDS instance: $instance." -ForegroundColor Red
                continue
            }

            $rdsCsv = Join-Path $outputPath "RDS_Instance_Metadata.csv"
            $dbClusterCsv = Join-Path $outputPath "DB_Cluster_Metadata.csv"

            Write-Host "Exporting RDS Instance Metadata..."
            $instanceMetadata | ForEach-Object {
                [PSCustomObject]@{
                    ID                                   = $_.ID
                    Class                                = $_.DBInstanceClass
                    Engine                               = $_.Engine
                    Status                               = $_.DBInstanceStatus
                    AllocatedStorage                     = $_.AllocatedStorage
                    Endpoint                             = $_.Endpoint
                    InstanceCreateTime                   = $_.InstanceCreateTime
                    AvailabilityZone                     = $_.AvailabilityZone
                    MultiAZ                              = $_.MultiAZ
                    StorageType                          = $_.StorageType
                    EngineVersion                        = $_.EngineVersion
                    AutoMinorVersionUpgrade              = $_.AutoMinorVersionUpgrade
                    ReadReplicaSourceDBInstanceIdentifier = if ($_.ReadReplicaSourceDBInstanceIdentifier) { $_.ReadReplicaSourceDBInstanceIdentifier } else { "None" }
                    ReadReplicaDBInstanceIdentifiers     = if ($_.ReadReplicaDBInstanceIdentifiers) { ($_.ReadReplicaDBInstanceIdentifiers -join ", ") } else { "None" }
                    LicenseModel                         = $_.LicenseModel
                    Iops                                 = if ($_.Iops) { $_.Iops } else { "N/A" }
                    OptionGroupMemberships               = if ($_.OptionGroupMemberships) { ($_.OptionGroupMemberships -join ", ") } else { "None" }
                    PubliclyAccessible                   = $_.PubliclyAccessible
                }
            } | Export-Csv -NoTypeInformation -Path $rdsCsv -Append

            Write-Host "RDS Instance Metadata exported to: $rdsCsv"

            # Get DB Cluster info (if exists)
            Write-Host "Gathering DB Cluster metadata for instance: $instance"
            $dbClusters = aws rds describe-db-clusters --db-cluster-identifier "$instance" --region $awsRegion --query "DBClusters[].{
                DBClusterIdentifier: DBClusterIdentifier,
                AllocatedStorage: AllocatedStorage,
                Status: Status,
                Endpoint: Endpoint,
                Engine: Engine,
                EngineVersion: EngineVersion
            }" --output json | ConvertFrom-Json

            if ($dbClusters) {
                Write-Host "Exporting DB Cluster Metadata..."
                $dbClusters | ForEach-Object {
                    [PSCustomObject]@{
                        DBClusterIdentifier       = $_.DBClusterIdentifier
                        DBClusterAllocatedStorage = $_.AllocatedStorage
                        DBClusterStatus           = $_.Status
                        DBClusterEndpoint         = $_.Endpoint
                        DBClusterEngine           = $_.Engine
                        DBClusterEngineVersion    = $_.EngineVersion
                    }
                } | Export-Csv -NoTypeInformation -Path $dbClusterCsv -Append

                Write-Host "DB Cluster Metadata exported to: $dbClusterCsv"
            } else {
                Write-Host "No DB Clusters found for RDS Instance: $instance." -ForegroundColor Yellow
            }

            Write-Host "=============================================================================================================="
        }

        if (-not (Test-Path $rdsCsv)) {
            Write-Host "FILE $rdsCsv is missing." -ForegroundColor Red
        } else {
            Write-Host "File $rdsCsv exists." -ForegroundColor Green
        }

        if (-not (Test-Path $dbClusterCsv)) {
            Write-Host "FILE $dbClusterCsv is missing." -ForegroundColor Red
        } else {
            Write-Host "File $dbClusterCsv exists." -ForegroundColor Green
        }
    }

    Write-Host "Information gathering completed with errors." -ForegroundColor Red

} catch {
    Write-Host "Information gathering for AWS completed  ." -ForegroundColor Green
} finally {
    Stop-Transcript
}

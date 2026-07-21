$folder = $PSScriptRoot

function Check-Command($cmdname) {
    return [bool](Get-Command -Name $cmdname -ErrorAction SilentlyContinue)
}

# Detect platform
$IsWindowsEnv = $PSVersionTable.OS -like "*Windows*" -or $PSVersionTable.PSEdition -eq 'Desktop'

# Initialize status variables
$status = "FAILED"
$comments = ""

# Function to install AWS CLI on Windows
function Install-AWSCLI-Windows {
    try {
        $installerUrl = "https://awscli.amazonaws.com/AWSCLIV2.msi"
        $installerPath = "$env:TEMP\AWSCLIV2.msi"

        Write-Host "Downloading AWS CLI installer..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -ErrorAction Stop

        Write-Host "Running installer..." -ForegroundColor Cyan
        Start-Process msiexec.exe -ArgumentList "/i `"$installerPath`" /quiet /norestart" -Wait

        Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue

        # Wait a bit and refresh PATH
        Start-Sleep -Seconds 5
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::Machine)

        return $true
    } catch {
        Write-Host " Error installing AWS CLI on Windows: $_" -ForegroundColor Red
        return $false
    }
}

# Function to install AWS CLI on Linux/macOS
function Install-AWSCLI-Unix {
    try {
        $tempDir = "/tmp/awscliv2"
        $zipPath = "$tempDir/awscliv2.zip"
        $installDir = "$tempDir/aws"

        if (-not (Test-Path $tempDir)) {
            New-Item -ItemType Directory -Path $tempDir | Out-Null
        }

        Write-Host "Downloading AWS CLI installer..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -OutFile $zipPath -ErrorAction Stop

        if (Test-Path $installDir) {
            Remove-Item -Recurse -Force $installDir
        }

        Expand-Archive -Path $zipPath -DestinationPath $tempDir -Force

        # Ensure sudo exists or run install without it
        $installCommand = "$installDir/install"
        if (Check-Command "sudo") {
            sudo $installCommand
        } else {
            & $installCommand
        }

        Remove-Item -Recurse -Force $tempDir
        return $true
    } catch {
        Write-Host " Error installing AWS CLI on Linux/macOS: $_" -ForegroundColor Red
        return $false
    }
}

# Check AWS CLI availability
if (Check-Command "aws") {
    Write-Host "`n AWS CLI is already installed." -ForegroundColor Green
    $status = "SUCCESS"
    $comments = "AWS CLI is already available."
} else {
    Write-Host "`n AWS CLI not found. Attempting installation..." -ForegroundColor Yellow

    if ($IsWindowsEnv) {
        if (Install-AWSCLI-Windows) {
            # Refresh PATH just in case
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::Machine)

            if (Check-Command "aws") {
                Write-Host " AWS CLI installed successfully on Windows." -ForegroundColor Green
                $status = "SUCCESS"
                $comments = "AWS CLI installed successfully on Windows."
            } else {
                Write-Host " AWS CLI installation failed on Windows." -ForegroundColor Red
                $comments = "AWS CLI installation failed on Windows. Check PATH or try manual install."
            }
        } else {
            $comments = "Installer execution failed."
        }
    } else {
        if (Install-AWSCLI-Unix) {
            if (Check-Command "aws") {
                Write-Host " AWS CLI installed successfully on Linux." -ForegroundColor Green
                $status = "SUCCESS"
                $comments = "AWS CLI installed successfully on Linux."
            } else {
                Write-Host " AWS CLI installation failed on Linux." -ForegroundColor Red
                $comments = "AWS CLI installation failed on Linux."
            }
        } else {
            $comments = "Installer execution failed."
        }
    }
}

# Output result object for main script
$Output = [PSCustomObject]@{
    Validation_Type = "Check AWS CLI Availability"
    Status = $status
    Comments = $comments
}

return $Output

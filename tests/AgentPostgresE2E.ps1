param(
    [string]$ApiBaseUrl = "http://localhost:5000",
    [int]$TimeoutSeconds = 120,
    [switch]$BuildImages,
    [string]$AdminEmail = $env:APP_ADMIN_EMAIL,
    [securestring]$AdminPassword = $(if ($env:APP_ADMIN_PASSWORD) {
        ConvertTo-SecureString $env:APP_ADMIN_PASSWORD -AsPlainText -Force
    } else { $null })
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$runId = "e2e-$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())-$([Guid]::NewGuid().ToString('N').Substring(0, 6))"
$agentContainer = "dbmr-$runId-agent"
$agentStarted = $false
$webSession = [Microsoft.PowerShell.Commands.WebRequestSession]::new()
$antiforgeryToken = $null

function Connect-Portal {
    if ([string]::IsNullOrWhiteSpace($AdminEmail) -or $null -eq $AdminPassword) {
        throw "Set APP_ADMIN_EMAIL and APP_ADMIN_PASSWORD, or pass -AdminEmail and -AdminPassword."
    }

    $loginToken = Invoke-RestMethod `
        -Method Get `
        -Uri "$ApiBaseUrl/api/auth/antiforgery" `
        -WebSession $webSession
    $plainPassword = [System.Net.NetworkCredential]::new('', $AdminPassword).Password
    try {
        Invoke-RestMethod `
            -Method Post `
            -Uri "$ApiBaseUrl/api/auth/login" `
            -WebSession $webSession `
            -ContentType "application/json" `
            -Headers @{ 'X-CSRF-TOKEN' = $loginToken.token } `
            -Body (@{ email = $AdminEmail; password = $plainPassword } | ConvertTo-Json) | Out-Null
    }
    finally {
        $plainPassword = $null
    }

    $script:antiforgeryToken = (Invoke-RestMethod `
        -Method Get `
        -Uri "$ApiBaseUrl/api/auth/antiforgery" `
        -WebSession $webSession).token
}

function Invoke-Api {
    param(
        [Parameter(Mandatory)] [ValidateSet("Get", "Post")] [string]$Method,
        [Parameter(Mandatory)] [string]$Path,
        [object]$Body
    )

    $request = @{
        Method = $Method
        Uri = "$ApiBaseUrl$Path"
        WebSession = $webSession
    }

    if ($Method -eq "Post") {
        $request.Headers = @{ 'X-CSRF-TOKEN' = $antiforgeryToken }
    }

    if ($null -ne $Body) {
        $request.ContentType = "application/json"
        $request.Body = $Body | ConvertTo-Json -Depth 10
    }

    Invoke-RestMethod @request
}

function Wait-ForApi {
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds(60)
    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        try {
            Invoke-RestMethod -Uri "$ApiBaseUrl/health" | Out-Null
            return
        }
        catch {
            Start-Sleep -Seconds 2
        }
    }

    throw "API did not become healthy within 60 seconds."
}

try {
    Push-Location $root

    docker info *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "Docker is unavailable or the daemon is not running."
    }

    if ($BuildImages) {
        & "$root\build.ps1"
        docker compose --profile agent build api agent-dev
        if ($LASTEXITCODE -ne 0) { throw "Docker image build failed." }
    }

    docker compose up -d postgres api worker frontend
    if ($LASTEXITCODE -ne 0) { throw "Docker Compose startup failed." }
    Wait-ForApi
    Connect-Portal

    Write-Host "Creating isolated test project $runId..."
    $customer = Invoke-Api -Method Post -Path "/api/customers" -Body @{
        name = $runId
        industry = "Integration Test"
        region = "Local"
    }

    $project = Invoke-Api -Method Post -Path "/api/projects" -Body @{
        customerId = $customer.customerId
        name = $runId
        description = "Docker agent end-to-end test"
        deploymentMode = "Standalone"
        createdBy = "AgentPostgresE2E"
    }

    $registration = Invoke-Api -Method Post -Path "/api/agents" -Body @{
        projectId = $project.projectId
        environmentId = $null
        name = $runId
        allowedPlugins = @("postgresql")
        pskMode = "SystemGenerated"
        userPsk = $null
        createdBy = "AgentPostgresE2E"
    }

    $credentials = @{
        host = "postgres"
        port = 5432
        database = "assessmentdb"
        username = "assessment"
        password = "assessment_dev_password"
    } | ConvertTo-Json -Compress

    $job = Invoke-Api -Method Post -Path "/api/agents/$($registration.agentId)/jobs" -Body @{
        databaseId = $null
        pluginId = "postgresql"
        parametersJson = $credentials
    }

    Write-Host "Starting agent container $agentContainer for job $($job.jobId)..."
    docker compose --profile agent run -d --name $agentContainer --no-deps `
        -e "AGENT_ID=$($registration.agentId)" `
        -e "AGENT_PSK=$($registration.bootstrapPackage.psk)" `
        -e "AGENT_BACKEND_URL=http://api:8080" `
        -e "AGENT_PLUGINS=postgresql" `
        agent-dev | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Agent container failed to start." }
    $agentStarted = $true

    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
    $completedJob = $null
    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        $jobs = @(Invoke-Api -Method Get -Path "/api/agents/$($registration.agentId)/jobs")
        $completedJob = $jobs | Where-Object { $_.jobId -eq $job.jobId }
        if ($completedJob.status -in @("Completed", "Failed")) { break }
        Start-Sleep -Seconds 2
    }

    if ($null -eq $completedJob) {
        throw "Job $($job.jobId) was not returned by the jobs endpoint."
    }
    if ($completedJob.status -ne "Completed") {
        throw "Job $($job.jobId) ended with status '$($completedJob.status)'."
    }

    $results = @(Invoke-Api -Method Get -Path "/api/agents/$($registration.agentId)/jobs/$($job.jobId)/results")
    if ($results.Count -ne 1) {
        throw "Expected one persisted result, received $($results.Count)."
    }

    $finding = $results[0].findingJson | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace($finding.server_version)) {
        throw "Persisted finding does not contain server_version."
    }

    Write-Host "PASS: PostgreSQL agent assessment completed and persisted." -ForegroundColor Green
    [pscustomobject]@{
        RunId = $runId
        ProjectId = $project.projectId
        AgentId = $registration.agentId
        JobId = $job.jobId
        PluginVersion = $results[0].pluginVersion
        ServerVersion = $finding.server_version
        FindingCount = $results.Count
    } | Format-List
}
catch {
    if ($agentStarted) {
        Write-Host "Agent logs:" -ForegroundColor Yellow
        docker logs $agentContainer 2>&1 | Select-Object -Last 50
    }
    throw
}
finally {
    if ($agentStarted) {
        docker rm -f $agentContainer *> $null
    }
    Pop-Location
}
param(
    [ValidateRange(1, 300)]
    [int]$TimeoutSeconds = 60
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$container = "dbmr-worker-smoke-$([Guid]::NewGuid().ToString('N'))"
$created = $false

Push-Location $root
try {
    docker info *> $null
    if ($LASTEXITCODE -ne 0) {
        throw 'Docker is unavailable or the daemon is not running.'
    }

    $running = @(docker compose ps --status running --services postgres api)
    if ($LASTEXITCODE -ne 0) { throw 'Could not inspect the disposable Compose stack.' }
    if ('postgres' -notin $running -or 'api' -notin $running) {
        throw 'Start the disposable PostgreSQL/API stack and wait for API migrations before running this test.'
    }

    $created = $true
    docker compose run -d --no-deps --name $container worker | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not start the isolated Worker container.' }

    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        $logs = (docker logs $container 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0) { throw 'Could not read Worker container logs.' }
        if ($logs -match '(?im)^\s*(fail|crit):|FileNotFoundException|FileLoadException|MissingMethodException|TypeLoadException') {
            throw "Worker reported a runtime failure:`n$logs"
        }

        $state = docker inspect --format '{{.State.Running}}' $container
        if ($LASTEXITCODE -ne 0) { throw 'Could not inspect Worker container state.' }
        if ($state -ne 'true') {
            throw "Worker exited before completing the database smoke test:`n$logs"
        }

        if ($logs -match '\[Status\] Agents active: \d+ \| Jobs pending: \d+ \| Jobs in-progress: \d+') {
            Write-Output 'PASS: Worker loaded its runtime dependencies and queried PostgreSQL agents and jobs.'
            return
        }

        Start-Sleep -Seconds 1
    }

    throw "Worker did not report successful PostgreSQL queries within $TimeoutSeconds seconds:`n$logs"
}
finally {
    try {
        if ($created) {
            docker rm -f $container | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "Could not remove Worker smoke container '$container'." }
        }
    }
    finally {
        Pop-Location
    }
}

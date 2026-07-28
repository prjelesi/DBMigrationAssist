# build.ps1 - Run this before 'docker compose build' or 'docker compose up'
# Builds all artifacts locally (where IT-approved tools are available),
# then Docker just packages the output — no network calls during docker build.

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot

Write-Host "`n=== Building .NET projects ===" -ForegroundColor Cyan

$projects = @(
    @{ Path = "src/backend/AssessmentToolkit.Api/AssessmentToolkit.Api.csproj";       Out = "src/backend/AssessmentToolkit.Api/publish" },
    @{ Path = "src/backend/AssessmentToolkit.Worker/AssessmentToolkit.Worker.csproj"; Out = "src/backend/AssessmentToolkit.Worker/publish" },
    @{ Path = "src/agent/AssessmentToolkit.Agent/AssessmentToolkit.Agent.csproj";     Out = "src/agent/AssessmentToolkit.Agent/publish" }
)

foreach ($p in $projects) {
    Write-Host "Publishing $($p.Path)..."
    dotnet publish "$root/$($p.Path)" -c Release -o "$root/$($p.Out)" --no-restore
    if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed for $($p.Path)" }
}

Write-Host "`n=== Building frontend ===" -ForegroundColor Cyan
Push-Location "$root/src/frontend"
npm run build
if ($LASTEXITCODE -ne 0) { throw "npm run build failed" }
Pop-Location

Write-Host "`n=== All artifacts built. Run: docker compose build ===" -ForegroundColor Green

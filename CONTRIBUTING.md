# Contributing

Contributions are welcome through issues and pull requests. This is a
community-maintained assessment toolkit, not a production support service.
There is no guaranteed response time or service-level agreement.

## Before opening an issue

- Check the [current limitations](docs/current/KNOWN_LIMITATIONS.md).
- Use fictional or redacted reproductions. Never attach customer assessment
  evidence, database dumps, passwords, agent bootstrap packages, or API keys.
- Report suspected vulnerabilities privately using [SECURITY.md](SECURITY.md),
  not a public issue.

## Development

Follow the [quick start](README.md#quick-start--local). Use .NET 8, Node.js 24
LTS, PowerShell 7, and Docker Compose. Install frontend dependencies with
`npm ci` so the committed lockfile is preserved.

Before submitting a change, run:

```powershell
dotnet restore .\src\AssessmentToolkit.sln
dotnet test .\src\AssessmentToolkit.sln --configuration Release
.\tests\DeploymentConfiguration.Tests.ps1
Push-Location .\src\frontend
npm ci
npm run lint
npm test
npm run build
Pop-Location
git diff --check
```

For container or agent changes, also run the Docker smoke checks described in
the [README](README.md#testing), against a disposable local environment.

Keep changes focused, add regression tests for behavior changes, and update
related documentation. Explain the purpose, validation performed, and any
compatibility or deployment implications in the pull request.

Only contribute code, documentation, and assets you have permission to
redistribute. Contributions are provided under the repository's
[MIT license](LICENSE); third-party components retain their own licenses.

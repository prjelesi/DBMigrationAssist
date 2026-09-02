# Operations and Deployment

**Reviewed:** 2026-09-02

## Local prerequisites

- Docker Desktop with Docker Compose.
- .NET 8 SDK.
- Node.js and npm compatible with `src/frontend/package.json`.
- Dependencies restored locally before running `build.ps1` because .NET publishing uses `--no-restore`.

## Local configuration

Create a repository-root `.env` containing strong, non-production-reused values:

```dotenv
POSTGRES_PASSWORD=<strong-local-password>
APP_ADMIN_EMAIL=admin@example.com
APP_ADMIN_PASSWORD=<strong-admin-password>
APP_ADMIN_DISPLAY_NAME=Administrator
WORKER_SERVICE_TOKEN=<long-random-service-token>
```

Do not commit `.env`.

Optional AI configuration can be supplied through API container environment variables or saved through the AI Settings page. The current Compose file contains commented literal examples rather than `.env` interpolation; uncomment and edit the `api.environment` entries, or add equivalent interpolation before starting the service:

```dotenv
AiFoundry__Endpoint=https://<resource>.openai.azure.com/
AiFoundry__ApiKey=<credential>
AiFoundry__Deployment=<deployment-name>
AiFoundry__ConnectivityCheckStartupDelaySeconds=5
AiFoundry__ConnectivityCheckIntervalMinutes=15
```

Use an HTTPS endpoint. The API performs a real model connectivity test five seconds after startup and every 15 minutes afterward; the timing values above are optional overrides. A successful manual or automatic test enables report generation, while a later successful check automatically recovers the status after a transient failure.

Report-generation policy is externalized through:

```dotenv
ReportGeneration__InstructionsPath=/app/config/report-instructions.md
ReportGeneration__RequireExternalInstructions=false
```

Docker Compose mounts the repository's `report-config` directory at `/app/config`. Azure mounts a dedicated
Azure Files share at the same path. The API reads the file for every report, so changes made directly or through
the AI Settings page take effect without rebuilding or restarting the application. Keep the mount writable when
using the administrator-only portal editor; a read-only mount remains supported for operator-managed on-premises installations.

### Report instructions editorial workflow

1. Sign in as an application administrator and open **AI Settings**.
2. Review the effective source, SHA-256 hash and current byte count before editing.
3. Save the Markdown policy. The API rejects content over 65,536 UTF-8 bytes.
4. If another editor or host process changed the file after it was loaded, refresh after the `409 Conflict` response and reconcile the changes.
5. Generate a new report to use the updated policy. Existing reports and evidence bundles are unchanged.

For operator-controlled installations, mount the file read-only and edit it through the host configuration process.
The portal displays the effective policy but disables saving. Set `ReportGeneration__RequireExternalInstructions=true`
when falling back to the packaged default is not acceptable.

## Build and start

Restore/install dependencies once when needed:

```powershell
dotnet restore .\src\AssessmentToolkit.sln
Push-Location .\src\frontend
npm install
Pop-Location
```

Build local artifacts, package images and start all default services:

```powershell
.\build.ps1
docker compose build
docker compose up -d
```

`build.ps1` publishes the API, worker and agent into their project `publish` directories and runs the frontend production build. The Dockerfiles package these prebuilt outputs; rerun the script before rebuilding images after source changes.

## Local endpoints

| Component | Address |
|---|---|
| Portal | `http://localhost:3000` |
| API | `http://localhost:5000` |
| Health | `http://localhost:5000/health` |
| Swagger | `http://localhost:5000/swagger` when running in `Development` |
| PostgreSQL | `localhost:5432`, database `assessmentdb`, user `assessment` |

## Compose services

| Service | Notes |
|---|---|
| `postgres` | PostgreSQL 16 with health check and durable `postgres_data`. |
| `api` | Runs migrations, provisions the configured administrator and local-agent bootstrap. |
| `worker` | Requires the same worker service token as the API. |
| `frontend` | Nginx-hosted portal and reverse proxy to the API. |
| `local-agent` | Auto-registering platform agent using shared bootstrap and local database configuration. |
| `agent-dev` | Optional profile for isolated tests with explicit agent ID and PSK. |

Use `local-agent` for the standard local demonstration. Its bootstrap is persisted in the `local_agent_bootstrap`
volume and reprovisioned by the API. Use `agent-dev` only for explicit manual-registration tests.

Start the optional development agent only when its identity and secret are configured:

```powershell
docker compose --profile agent up -d agent-dev
```

The API must also have the matching raw PSK at `AgentPsk:<agent-id>`. Portal registration writes this value only to the running API process. After an API restart, manually registered agents cannot authenticate unless the raw PSK is supplied through configuration or the agent is re-registered; the persisted salted hash is not sufficient for the current verifier.

## Durable local data

| Volume/path | Content |
|---|---|
| `postgres_data` | Application PostgreSQL database. |
| `evidence_data` | Uploaded evidence files. |
| `data_protection_keys` | ASP.NET Core Data Protection keys. |
| `local_agent_bootstrap` | Platform-local agent bootstrap. |
| `local-agent/databases.json` | Plaintext local database connection details mounted read-only into the agent. |
| `report-config/report-instructions.md` | Live report-generation policy mounted into the API. |

`docker compose down` retains named volumes. `docker compose down -v` deletes local application data and should be treated as destructive.

Protect `local-agent/databases.json` with host permissions. A read-only container mount prevents container writes; it does not encrypt credentials.

## Health and smoke checks

```powershell
docker compose ps
Invoke-RestMethod http://localhost:5000/health
Invoke-WebRequest http://localhost:3000
```

After signing in, verify the System page reports API and database health and the expected AI readiness state. The displayed worker value is currently a static `Running` response, not a worker heartbeat or liveness probe. `Not configured` is valid when AI features are intentionally disabled; it means report generation is unavailable.

Run the PostgreSQL connected-agent E2E test against a disposable target using the parameters documented in `tests/AgentPostgresE2E.ps1`.

## Common operational behavior

- The API applies pending EF Core migrations on startup. Back up production data before deploying schema changes.
- The worker and API must share `Worker:ServiceToken`.
- The local agent must be able to read its bootstrap volume and local database configuration.
- Rebuilding or redeploying images does not copy PostgreSQL data between environments.
- Dashboard labels may suggest estate-wide counts while some values are scoped to the first accessible project.

## Azure architecture

The subscription-scoped Bicep deployment under `infra/` declares:

- Resource group and virtual network.
- User-assigned managed identity.
- Azure Container Registry.
- Azure Files-backed storage for evidence, Data Protection keys, local-agent bootstrap and report instructions.
- Key Vault and role assignments.
- PostgreSQL Flexible Server and application database.
- Container Apps environment.
- API, worker, frontend and platform discovery-agent Container Apps.

The Azure environment has its own database and file storage. It is not a replica of local Compose.

## Azure parameters

`infra/main.bicep` currently accepts:

| Parameter | Purpose |
|---|---|
| `environmentName` | Environment tag value. |
| `location` | Azure region. |
| `sessionId`, `deployedBy`, `createdAt` | Deployment metadata tags. |
| `deployerObjectId` | Principal used by deployment role assignments. |
| `postgresAdminPassword` | Secure PostgreSQL administrator password. |
| `appAdminEmail` | Initial application administrator email. |
| `appAdminPassword` | Secure initial administrator password. |
| `appAdminDisplayName` | Initial administrator display name. |
| `workerServiceToken` | Secure shared worker/API token. |
| `configureSecrets` | Enables Key Vault secret creation. Defaults to `false`. |
| `containerImage` | Common fallback image. Defaults to a hello-world image. |
| `apiContainerImage` | Exact API image reference. |
| `workerContainerImage` | Exact worker image reference. |
| `frontendContainerImage` | Exact frontend image reference. |
| `discoveryAgentContainerImage` | Exact platform discovery-agent image reference. |

A functional deployment must provide the exact validated application images. Leaving the image defaults unchanged deploys a sample image, not this application. Set `configureSecrets=true` when deploying the application with Key Vault-backed configuration.

## Deployment discipline

1. Build and test the source locally.
2. Build API, worker, frontend and agent images from the same source revision.
3. Push immutable image tags to the target registry.
4. Validate Bicep and deployment parameters.
5. Deploy infrastructure/application revisions with the exact immutable tags.
6. Confirm migrations, health, login, report listing and worker authentication.
7. Review API and worker logs for startup, authorization and migration failures.

Do not infer that an Azure resource is deployed or healthy only because it exists in Bicep. Runtime status must be checked in the target subscription.

## Image-only application releases

Routine application releases do not require a Bicep deployment. Build, publish, and activate all four application images with:

```powershell
.\infra\deploy.ps1 -Mode ReleaseImages
```

This mode builds and smoke-runs the local API, worker, frontend, and discovery agent images; pushes each image to ACR with both an immutable UTC timestamp tag and the `latest` alias; and updates the existing Container Apps to the immutable tag. It does not redeploy the resource group, network, PostgreSQL server, Key Vault, storage, managed environment, identities, or role assignments.

Container Apps intentionally run the immutable tag. The `latest` tag is available for discovery and manual use, but pushing a new image to an existing mutable tag does not by itself create a Container Apps revision. Always use `ReleaseImages` to activate a release. Use the regular Bicep deployment workflow only when infrastructure or application configuration changes.

### Current development deployment

The development application release was last verified on 2026-09-02 with immutable image tag `20260902082359`.
The image-only release updated all four Container Apps and returned HTTP 200 from the portal and API health endpoint.
The infrastructure and PostgreSQL Flexible Server were not redeployed by this release.

Discover the current endpoints from Azure:

```powershell
$resourceGroup = 'rg-dbmigratio-dev-1fa1'
az containerapp list --resource-group $resourceGroup `
	--query "[].{name:name,fqdn:properties.configuration.ingress.fqdn,image:properties.template.containers[0].image}" `
	--output table
```

Current portal: `https://ca-web-dbmigratio-dev-1fa1.whitetree-ce541b55.swedencentral.azurecontainerapps.io`

## Backup and recovery

The repository does not contain a complete tested production backup/restore runbook. Production operation requires separate PostgreSQL backup/restore validation, evidence-share retention, Data Protection key protection and recovery testing.
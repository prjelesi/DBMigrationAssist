# DB Migration Assessment Toolkit

A self-hosted portal for assessing database estates before migration to the cloud. Lightweight Docker agents are deployed inside customer networks, collect findings from source databases, and upload signed result bundles to the portal for AI-assisted analysis and report generation.

---

## Table of contents

- [DB Migration Assessment Toolkit](#db-migration-assessment-toolkit)
  - [Table of contents](#table-of-contents)
  - [Architecture](#architecture)
  - [Prerequisites](#prerequisites)
  - [Quick start — local](#quick-start--local)
  - [Portal walkthrough](#portal-walkthrough)
  - [Deploying assessment agents](#deploying-assessment-agents)
    - [1. Register an agent in the portal](#1-register-an-agent-in-the-portal)
    - [2. Choose a deployment method](#2-choose-a-deployment-method)
    - [3. Docker run (simplest)](#3-docker-run-simplest)
    - [4. Docker Compose profile (local PoC)](#4-docker-compose-profile-local-poc)
    - [5. bootstrap.json file](#5-bootstrapjson-file)
    - [6. Kubernetes / bare-metal](#6-kubernetes--bare-metal)
  - [End-to-end test](#end-to-end-test)
  - [Database account requirements](#database-account-requirements)
    - [PostgreSQL](#postgresql)
    - [Oracle](#oracle)
  - [Enabling AI features](#enabling-ai-features)
    - [Option A — Environment variables (recommended)](#option-a--environment-variables-recommended)
    - [Option B — Portal UI](#option-b--portal-ui)
    - [Verifying AI is active](#verifying-ai-is-active)
  - [Azure deployment](#azure-deployment)
    - [Parameters](#parameters)
    - [Deploy steps](#deploy-steps)
  - [Configuration reference](#configuration-reference)
    - [API (`src/backend/AssessmentToolkit.Api`)](#api-srcbackendassessmenttoolkitapi)
    - [Worker (`src/backend/AssessmentToolkit.Worker`)](#worker-srcbackendassessmenttoolkitworker)
    - [Agent (`src/agent/AssessmentToolkit.Agent`)](#agent-srcagentassessmenttoolkitagent)
  - [Security notes](#security-notes)

---

## Architecture

```
  Customer network                    Portal (Docker / Azure Container Apps)
  ─────────────────                   ─────────────────────────────────────
  ┌────────────────┐  HTTPS + HMAC    ┌──────────┐  ┌──────────┐
  │  Agent         │ ──────────────►  │  API     │  │  Worker  │
  │  (Docker)      │                  │ :5000    │  │          │
  │                │                  └──────────┘  └──────────┘
  │  Plugins:      │                       │               │
  │  · postgresql  │                  ┌────▼───────────────▼───┐
  │  · oracle      │                  │  PostgreSQL :5432       │
  └────────────────┘                  └────────────────────────┘
                                           ▲
                                      ┌────┴───────┐
                                      │  Frontend  │
                                      │ :3000      │
                                      └────────────┘
```

| Container | Purpose |
|-----------|---------|
| `api` | REST API — portal backend, job dispatch, evidence, AI enrichment |
| `worker` | Background services — heartbeat monitor, job timeout, AI auto-enrichment |
| `frontend` | React portal UI served via nginx |
| `postgres` | PostgreSQL 16 — all portal data |
| `agent` | Deployed **inside the customer network** — polls for jobs, runs plugins |

---

## Prerequisites

| Tool | Version |
|------|---------|
| Docker Desktop (or Docker Engine + Compose) | 24 + |
| .NET SDK | 8.0 (build only) |
| Node.js + npm | 20 + (build only) |
| PowerShell | 7 + |

> **Note:** The Docker images are built from pre-compiled output. You must run `build.ps1` on a machine with the SDKs before running `docker compose build`.

---

## Quick start — local

```powershell
# 1. Build all artifacts (requires .NET 8 SDK + Node 20)
cd c:\github\DBMigrationReady
dotnet restore src/AssessmentToolkit.sln
.\build.ps1

# 2. Build Docker images
docker compose build

# 3. Start the stack
docker compose up -d

# 4. Open the portal
start http://localhost:3000
```

The API is available at `http://localhost:5000` (Swagger UI at `/swagger`).

On first start, EF Core migrations run automatically and all database schemas are created.

---

## Portal walkthrough

| Section | Route | Description |
|---------|-------|-------------|
| Dashboard | `/` | Counts of projects, agents, databases |
| System | `/system` | Health status, AI configuration, system config |
| Projects | `/projects` | Create and manage migration projects |
| Environments | `/environments` | DEV / UAT / PROD environment rings |
| DB Inventory | `/inventory` | Register source databases with engine, host, criticality |
| Agents | `/agents` | Register agents, dispatch jobs, view findings |
| Communication Map | `/communication-map` | ReactFlow graph of database dependencies |
| Portfolio | `/portfolio` | Group databases into migration waves |
| Questionnaire | `/questionnaire` | Structured discovery questionnaires |
| Evidence | `/evidence` | Upload AWR / Statspack / DMA report files |
| Reports | `/reports` | AI-generated migration assessment reports |
| AI Settings | `/ai-settings` | Configure Azure OpenAI / AI Foundry |

---

## Deploying assessment agents

The agent is a .NET 8 background service that runs **inside the customer network** alongside the source databases. It polls the portal for jobs, runs the appropriate plugin against the target database, and uploads a signed result bundle over HTTPS.

### 1. Register an agent in the portal

1. Navigate to **Agents** and select a project.
2. Click **+ Register Agent**.
3. Fill in:
   - **Agent Name** — a descriptive label (e.g. `Prod-Oracle-Agent-1`)
   - **Allowed Plugins** — tick `postgresql` and/or `oracle`
   - **PSK Mode** — `System generated` (recommended) or `User supplied`
4. Click **Register Agent**.
5. A **bootstrap package** is shown **once** — copy or download it immediately:

```json
{
  "agentId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "backendUrl": "https://your-portal-api-url",
  "psk": "your-pre-shared-key",
  "allowedPlugins": ["postgresql", "oracle"],
  "issuedAt": "2026-07-28T10:00:00Z"
}
```

> **Security:** The PSK is shown once and never stored in recoverable form. Store it in a secrets manager or environment variable before closing the dialog.

---

### 2. Choose a deployment method

| Method | Best for |
|--------|----------|
| [Docker run](#3-docker-run-simplest) | Single-machine quick deployment |
| [Docker Compose profile](#4-docker-compose-profile-local-poc) | Local PoC alongside the portal |
| [bootstrap.json file](#5-bootstrapjson-file) | Air-gapped or restricted environments |
| [Kubernetes](#6-kubernetes--bare-metal) | Production / enterprise deployments |

---

### 3. Docker run (simplest)

Pull and run the agent image with environment variables from the bootstrap package:

```bash
docker run -d \
  --name dbmr-agent \
  --restart unless-stopped \
  -e AGENT_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" \
  -e AGENT_PSK="your-pre-shared-key" \
  -e AGENT_BACKEND_URL="https://your-portal-api-url" \
  -e AGENT_PLUGINS="postgresql,oracle" \
  dbmigrationready-agent:latest
```

**Environment variables:**

| Variable | Required | Description |
|----------|----------|-------------|
| `AGENT_ID` | ✅ | Agent GUID from the bootstrap package |
| `AGENT_PSK` | ✅ | Pre-shared key from the bootstrap package |
| `AGENT_BACKEND_URL` | ✅ | Base URL of the portal API (no trailing slash) |
| `AGENT_PLUGINS` | optional | Comma-separated list of plugins to enable. Default: `postgresql,oracle` |
| `AGENT_BOOTSTRAP_PATH` | optional | Path to a `bootstrap.json` file (overrides env vars above) |

> **Network:** The agent only makes **outbound** HTTPS calls to `AGENT_BACKEND_URL`. No inbound ports are required. Ensure outbound TCP/443 is open from the agent host to the portal.

---

### 4. Docker Compose profile (local PoC)

The `docker-compose.yml` includes an `agent-dev` service under the `agent` profile. To use it:

1. Edit `docker-compose.yml` and fill in `AGENT_ID` and `AGENT_PSK` from the bootstrap package:

```yaml
agent-dev:
  environment:
    AGENT_BACKEND_URL: "http://api:8080"
    AGENT_ID: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"   # ← paste here
    AGENT_PSK: "your-pre-shared-key"                    # ← paste here
    AGENT_PLUGINS: "postgresql,oracle"
```

2. Start with the `agent` profile:

```powershell
docker compose --profile agent up -d
```

> **Note:** `AGENT_BACKEND_URL` uses the internal Docker network name `api` when running alongside the portal stack.

---

### 5. bootstrap.json file

For air-gapped environments where injecting env vars is inconvenient, save the bootstrap package as `bootstrap.json` and mount it into the container:

```bash
# Save the bootstrap package to a file
cat > bootstrap.json << 'EOF'
{
  "agentId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "backendUrl": "https://your-portal-api-url",
  "psk": "your-pre-shared-key",
  "allowedPlugins": ["postgresql", "oracle"]
}
EOF

docker run -d \
  --name dbmr-agent \
  --restart unless-stopped \
  -v $(pwd)/bootstrap.json:/app/bootstrap.json:ro \
  dbmigrationready-agent:latest
```

The agent looks for `bootstrap.json` in `/app/` by default, or at the path set in `AGENT_BOOTSTRAP_PATH`.

---

### 6. Kubernetes / bare-metal

Create a Kubernetes Secret from the bootstrap values and reference it in a Deployment:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: dbmr-agent-bootstrap
type: Opaque
stringData:
  AGENT_ID: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  AGENT_PSK: "your-pre-shared-key"
  AGENT_BACKEND_URL: "https://your-portal-api-url"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dbmr-agent
spec:
  replicas: 1
  selector:
    matchLabels:
      app: dbmr-agent
  template:
    metadata:
      labels:
        app: dbmr-agent
    spec:
      containers:
        - name: agent
          image: dbmigrationready-agent:latest
          envFrom:
            - secretRef:
                name: dbmr-agent-bootstrap
          env:
            - name: AGENT_PLUGINS
              value: "postgresql,oracle"
```

> Each registered agent should have its own bootstrap package. Running multiple replicas of the same agent GUID is not supported.

---

## End-to-end test

The PostgreSQL smoke test creates an isolated customer, project, agent, and job; starts the real agent container; assesses the Compose PostgreSQL instance; and verifies that a finding containing `server_version` is persisted.

```powershell
# Build current binaries and images, then run the test
.\tests\AgentPostgresE2E.ps1 -BuildImages

# Re-run against already-built images
.\tests\AgentPostgresE2E.ps1
```

The temporary agent container is removed automatically. Test records use unique `e2e-*` names so repeated runs do not conflict.

---

## Database account requirements

The agent uses a **read-only** dedicated account. Never use `sa`, `SYS`, or a DBA account.

### PostgreSQL

```sql
-- Create a dedicated assessment user
CREATE USER assessment_reader WITH PASSWORD 'strong-password-here';

-- Grant read access to all existing tables
GRANT CONNECT ON DATABASE your_database TO assessment_reader;
GRANT USAGE ON SCHEMA public TO assessment_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO assessment_reader;

-- Ensure new tables are also accessible
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT ON TABLES TO assessment_reader;
```

The agent also queries system views (`pg_database`, `pg_extension`, `information_schema`) which are readable by any login role.

### Oracle

```sql
-- Create a dedicated assessment user
CREATE USER assessment_reader IDENTIFIED BY "strong-password-here";
GRANT CREATE SESSION TO assessment_reader;

-- System views required by all collections
GRANT SELECT ON V_$VERSION   TO assessment_reader;
GRANT SELECT ON V_$DATABASE  TO assessment_reader;
GRANT SELECT ON V_$SESSION   TO assessment_reader;

-- DBA views required for schema/object inventory (recommended)
GRANT SELECT ON DBA_USERS    TO assessment_reader;
GRANT SELECT ON DBA_OBJECTS  TO assessment_reader;
GRANT SELECT ON DBA_DATA_FILES TO assessment_reader;
GRANT SELECT ON DBA_FREE_SPACE TO assessment_reader;
GRANT SELECT ANY DICTIONARY  TO assessment_reader;  -- convenience grant

-- AWR (optional — requires Diagnostics Pack licence)
GRANT SELECT ON DBA_HIST_SNAPSHOT TO assessment_reader;
```

> If `DBA_` views are not accessible, the agent falls back to a partial collection and reports lower confidence findings.

---

## Enabling AI features

AI enrichment and report generation use **Azure OpenAI** (or any Azure AI Foundry deployment). Without AI configuration the portal works fully — AI features simply show a warning banner.

### Option A — Environment variables (recommended)

Add to `docker-compose.yml` under the `api` service:

```yaml
environment:
  AiFoundry__Endpoint: "https://<your-resource>.openai.azure.com/"
  AiFoundry__Deployment: "gpt-4o"
  # API key — never commit to source control
  AZURE_OPENAI_API_KEY: "<your-api-key>"
```

### Option B — Portal UI

1. Go to **AI Settings** (`/ai-settings`).
2. Enter the endpoint and deployment name.
3. The API key must still be set via environment variable — it is never stored in the database.

### Verifying AI is active

```bash
curl http://localhost:5000/api/ai/status
# {"available":true,"message":"AI Foundry is configured and available."}
```

Once configured, the worker automatically enriches completed assessment results with migration path recommendations, risk analysis, and remediation steps.

---

## Azure deployment

Production deployment uses Azure Container Apps via the Bicep template in `infra/main.bicep`.

### Parameters

| Parameter | Description |
|-----------|-------------|
| `location` | Azure region (default: resource group location) |
| `environmentName` | Base name for all resources |
| `postgresAdminPassword` | Password for the PostgreSQL Flexible Server admin account |
| `acrServer` | Azure Container Registry login server (e.g. `myregistry.azurecr.io`) |
| `acrUsername` | ACR username |
| `acrPassword` | ACR password (marked `@secure`) |

### Deploy steps

```powershell
# 1. Create a resource group
az group create --name rg-dbmr --location uksouth

# 2. Build and push images to your ACR
az acr build --registry myregistry --image dbmr-api:latest     ./src/backend/AssessmentToolkit.Api
az acr build --registry myregistry --image dbmr-worker:latest  ./src/backend/AssessmentToolkit.Worker
az acr build --registry myregistry --image dbmr-frontend:latest ./src/frontend
az acr build --registry myregistry --image dbmr-agent:latest   ./src/agent/AssessmentToolkit.Agent

# 3. Deploy infrastructure
az deployment group create \
  --resource-group rg-dbmr \
  --template-file infra/main.bicep \
  --parameters \
      environmentName=assessment-toolkit \
      postgresAdminPassword='<secure-password>' \
      acrServer=myregistry.azurecr.io \
      acrUsername=myregistry \
      acrPassword='<acr-password>'
```

After deployment, retrieve the API URL:

```powershell
az containerapp show \
  --resource-group rg-dbmr \
  --name assessment-toolkit-api \
  --query properties.configuration.ingress.fqdn \
  --output tsv
```

Use that URL as `AGENT_BACKEND_URL` when configuring agents against the cloud deployment.

---

## Configuration reference

### API (`src/backend/AssessmentToolkit.Api`)

| Key | Description | Default |
|-----|-------------|---------|
| `ConnectionStrings__Postgres` | PostgreSQL connection string | — |
| `Api__PublicUrl` | Public base URL returned in bootstrap packages | Request origin |
| `Evidence__StorageRoot` | Directory for uploaded evidence files | `/app/evidence` |
| `AiFoundry__Endpoint` | Azure OpenAI endpoint URL | — |
| `AiFoundry__Deployment` | Model deployment name (e.g. `gpt-4o`) | — |
| `AZURE_OPENAI_API_KEY` | Azure OpenAI API key (env var only) | — |

### Worker (`src/backend/AssessmentToolkit.Worker`)

| Key | Description | Default |
|-----|-------------|---------|
| `ConnectionStrings__Postgres` | PostgreSQL connection string | — |
| `Worker__ApiBaseUrl` | Internal URL of the API service | — |

### Agent (`src/agent/AssessmentToolkit.Agent`)

| Variable | Description |
|----------|-------------|
| `AGENT_ID` | Agent GUID (from bootstrap package) |
| `AGENT_PSK` | Pre-shared key (from bootstrap package) |
| `AGENT_BACKEND_URL` | Portal API base URL |
| `AGENT_PLUGINS` | Comma-separated plugin IDs: `postgresql`, `oracle` |
| `AGENT_BOOTSTRAP_PATH` | Path to `bootstrap.json` (alternative to env vars) |

---

## Security notes

- All agent-to-backend communication is authenticated with **HMAC-SHA256** (method + path + timestamp + body hash).
- Timestamps are validated within a ±5 minute window to prevent replay attacks.
- PSKs are stored as **salted SHA-256 hashes** in the database — the raw value is shown once at registration and never recoverable.
- Use TLS in production — the portal API should be served behind HTTPS; the agent verifies the server certificate.
- The evidence storage volume should be backed up regularly; it holds uploaded AWR and Statspack files.

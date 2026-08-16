# DB Migration Assessment Toolkit

A self-hosted portal for assessing database estates before migration to the cloud. Lightweight Docker Discovery Agents are deployed inside customer networks, collect findings from source databases, and upload signed result bundles to the portal for AI-assisted analysis and report generation.

---

## Table of contents

- [DB Migration Assessment Toolkit](#db-migration-assessment-toolkit)
  - [Table of contents](#table-of-contents)
  - [Architecture](#architecture)
  - [Prerequisites](#prerequisites)
  - [Quick start — local](#quick-start--local)
  - [Portal walkthrough](#portal-walkthrough)
  - [Offline database assessment](#offline-database-assessment)
  - [Questionnaire templates](#questionnaire-templates)
  - [Deploying Discovery Agents](#deploying-discovery-agents)
    - [Supported plugins](#supported-plugins)
    - [1. Register a Discovery Agent in the portal](#1-register-a-discovery-agent-in-the-portal)
    - [2. Choose a deployment method](#2-choose-a-deployment-method)
    - [Build the agent image](#build-the-agent-image)
    - [3. Docker run (simplest)](#3-docker-run-simplest)
    - [4. Docker Compose profile (local PoC)](#4-docker-compose-profile-local-poc)
    - [5. bootstrap.json file](#5-bootstrapjson-file)
    - [6. Kubernetes / bare-metal](#6-kubernetes--bare-metal)
  - [Discovery Agent user instructions](#discovery-agent-user-instructions)
    - [Configure database credentials](#configure-database-credentials)
    - [Start and verify the agent](#start-and-verify-the-agent)
    - [Dispatch an assessment](#dispatch-an-assessment)
    - [View findings](#view-findings)
    - [Troubleshooting](#troubleshooting)
  - [End-to-end test](#end-to-end-test)
  - [Database account requirements](#database-account-requirements)
    - [PostgreSQL](#postgresql)
    - [Oracle](#oracle)
    - [SQL Server](#sql-server)
    - [MySQL / MariaDB](#mysql--mariadb)
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
  ┌────────────────┐  HTTPS + HMAC    ┌──────────┐       ┌────────────────┐
  │ Agent          │ ──────────────►  │ API      │ ────► │ PostgreSQL     │
  │                │                  │ :5000    │       │ :5432          │
  │ Plugins:       │                  └────▲─────┘       └───────▲────────┘
  │ · postgresql   │                       │                     │
  │ · oracle       │                  ┌────┴─────┐         ┌─────┴────┐
  │ · sqlserver    │                  │ Frontend │         │ Worker   │
  │ · mysql        │                  │ :3000    │         │          │
  └────────────────┘                  └──────────┘         └──────────┘
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
| Dashboard | `/` | Counts of projects, Discovery Agents, databases |
| System | `/system` | Health status, AI configuration, system config |
| Projects | `/projects` | Create and manage migration projects |
| Environments | `/environments` | DEV / UAT / PROD environment rings |
| DB Inventory | `/inventory` | Register source databases with engine, host, criticality |
| Discovery Agents | `/agents` | Register Discovery Agents, dispatch jobs, view findings |
| Communication Map | `/communication-map` | ReactFlow graph of database dependencies |
| Portfolio | `/portfolio` | Group databases into migration waves |
| Questionnaire | `/questionnaire` | Versioned baseline and database-specific discovery questionnaires |
| Evidence | `/evidence` | Upload assessment reports and questionnaire supporting documents |
| Reports | `/reports` | AI-generated migration assessment reports |
| AI Settings | `/ai-settings` | Configure Azure OpenAI / AI Foundry |

---

## Offline database assessment

Use this workflow when a Discovery Agent cannot reach a database:

1. Create the database definition in **DB Inventory**.
2. In that database row, select **Download offline assessment script** and transfer the generated PowerShell script to the customer.
3. Install the database's native command-line client on the execution host, then run the script with a read-only database account:

```powershell
pwsh ./collect-<database>-assessment.ps1 -Username <read-only-user>
```

4. Enter the password at the secure prompt. The script writes an assessment JSON file beside the script; it does not store the password.
5. Have the customer return the JSON file. In the same database row, select **Upload assessment result** and upload it.

The collector embeds the inventory database ID and engine plugin. The portal rejects a result uploaded against a different database, an incompatible engine, an unsupported schema version, a non-JSON file, or a file larger than 10 MB. Uploaded results are stored as unverified assessments until reviewed.

---

## Questionnaire templates

Questionnaires are defined as versioned JSON files in `src/backend/AssessmentToolkit.Api/QuestionnaireTemplates/`. The portal includes a generic baseline plus supplemental templates for Oracle, PostgreSQL, SQL Server, and MySQL. Use **Sync JSON templates** on the Questionnaire page to import new template versions; existing versions and their responses are preserved.

Each question supports `Text`, `Textarea`, `Select`, `MultiSelect`, `Boolean`, or `Number`. The following optional capabilities are controlled per question:

```json
{
  "text": "Which database features are business-critical?",
  "type": "MultiSelect",
  "required": true,
  "allowCustomAnswer": true,
  "allowAttachments": true,
  "options": ["RAC", "Data Guard", "GoldenGate", "None"]
}
```

- `allowCustomAnswer` adds an **Other / custom answer** field and is valid only for `Select` and `MultiSelect` questions.
- `allowAttachments` lets the respondent upload supporting documents up to 50 MB. Files remain visible in the project Evidence Library and are linked to the response and question.
- An attachment satisfies a required attachment-enabled question when no text answer is supplied.
- Documents can be downloaded at any time, but answers and attachments become read-only after submission.

Increment `version` when changing a template that may already have responses. Do not replace a synchronized version in place.

---

## Deploying Discovery Agents

The Discovery Agent is a .NET 8 background service that runs **inside the customer network** alongside the source databases. It polls the portal for jobs, runs the appropriate plugin against the target database, and uploads a signed result bundle over HTTPS.

### Supported plugins

| Plugin ID | Source database | Default port | Status |
|-----------|-----------------|--------------|--------|
| `postgresql` | PostgreSQL | 5432 | Supported |
| `oracle` | Oracle Database | 1521 | Supported |
| `sqlserver` | Microsoft SQL Server | 1433 | Supported |
| `mysql` | MySQL / MariaDB | 3306 | Supported |

MongoDB may appear in inventory data or the portal selector, but an executable MongoDB Discovery Agent plugin is not yet included. Do not enable `mongodb` on deployed Discovery Agents.

### 1. Register a Discovery Agent in the portal

1. Navigate to **Discovery Agents** and select a project.
2. Click **+ Register Discovery Agent**.
3. Fill in:
  - **Discovery Agent Name** — a descriptive label (e.g. `Prod-Oracle-Discovery-1`)
  - **Allowed Plugins** — select only the engines this Discovery Agent can reach: `postgresql`, `oracle`, `sqlserver`, and/or `mysql`
   - **PSK Mode** — `System generated` (recommended) or `User supplied`
4. Click **Register Discovery Agent**.
5. A **bootstrap package** is shown **once** — copy or download it immediately:

```json
{
  "agentId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "backendUrl": "https://your-portal-api-url",
  "psk": "your-pre-shared-key",
  "allowedPlugins": ["postgresql", "oracle", "sqlserver", "mysql"],
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

### Build the agent image

The agent Dockerfile copies pre-published .NET output. Build and publish before creating the image:

```powershell
cd c:\github\DBMigrationReady
.\build.ps1
docker build -t dbmigrationready-agent:latest .\src\agent\AssessmentToolkit.Agent
```

For a shared registry, tag and push the image, then use that registry name in the deployment examples:

```powershell
docker tag dbmigrationready-agent:latest registry.example.com/dbmigrationready-agent:1.0
docker push registry.example.com/dbmigrationready-agent:1.0
```

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
  -e AGENT_PLUGINS="postgresql,oracle,sqlserver,mysql" \
  dbmigrationready-agent:latest
```

**Environment variables:**

| Variable | Required | Description |
|----------|----------|-------------|
| `AGENT_ID` | ✅ | Agent GUID from the bootstrap package |
| `AGENT_PSK` | ✅ | Pre-shared key from the bootstrap package |
| `AGENT_BACKEND_URL` | ✅ | Base URL of the portal API (no trailing slash) |
| `AGENT_PLUGINS` | optional | Comma-separated implemented plugin IDs. Default: `postgresql,oracle` |
| `AGENT_BOOTSTRAP_PATH` | optional | Path to a `bootstrap.json` file (overrides env vars above) |
| `AGENT_DATABASES_PATH` | optional | Path to the local database credential file. Default: `databases.json` |

> **Network:** The agent only makes **outbound** HTTPS calls to `AGENT_BACKEND_URL`. No inbound ports are required. Ensure outbound TCP/443 is open from the agent host to the portal.

---

### 4. Platform Local Agent

The default Docker Compose stack includes one **Platform Local Agent**. The API provisions its identity and PSK into a private Docker volume, and the agent reuses that identity across container restarts. It appears in Discovery Agents for every project and supports all four implemented plugins.

```powershell
docker compose up -d
```

Use Compose service names such as `postgres` for databases in the same Docker network. Use `host.docker.internal` for a database running directly on the Docker host. Ad-hoc credentials can be supplied when dispatching a job; for locally held credentials, see `local-agent/databases.example.json`.

### 5. Docker Compose profile (isolated testing)

The `docker-compose.yml` retains an `agent-dev` service under the `agent` profile for isolated tests with temporary or manually registered identities. To use it:

1. Edit `docker-compose.yml` and fill in `AGENT_ID` and `AGENT_PSK` from the bootstrap package:

```yaml
agent-dev:
  environment:
    AGENT_BACKEND_URL: "http://api:8080"
    AGENT_ID: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"   # ← paste here
    AGENT_PSK: "your-pre-shared-key"                    # ← paste here
    AGENT_PLUGINS: "postgresql,oracle,sqlserver,mysql"
```

2. Start with the `agent` profile:

```powershell
docker compose --profile agent up -d
```

> **Note:** `AGENT_BACKEND_URL` uses the internal Docker network name `api` when running alongside the portal stack.

---

### 6. bootstrap.json file

For air-gapped environments where injecting env vars is inconvenient, save the bootstrap package as `bootstrap.json` and mount it into the container:

```bash
# Save the bootstrap package to a file
cat > bootstrap.json << 'EOF'
{
  "agentId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "backendUrl": "https://your-portal-api-url",
  "psk": "your-pre-shared-key",
  "allowedPlugins": ["postgresql", "oracle", "sqlserver", "mysql"]
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

### 7. Kubernetes / bare-metal

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
              value: "postgresql,oracle,sqlserver,mysql"
```

> Each registered agent should have its own bootstrap package. Running multiple replicas of the same agent GUID is not supported.

For bare-metal Linux, copy the contents of `src/agent/AssessmentToolkit.Agent/publish` to the target host, install the .NET 8 runtime, set the bootstrap environment variables, and run:

```bash
cd /opt/dbmr-agent
export AGENT_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
export AGENT_PSK="your-pre-shared-key"
export AGENT_BACKEND_URL="https://your-portal-api-url"
export AGENT_PLUGINS="postgresql,oracle,sqlserver,mysql"
dotnet AssessmentToolkit.Agent.dll
```

For a persistent service, place these variables in a root-readable environment file and configure systemd with `WorkingDirectory=/opt/dbmr-agent`, `ExecStart=/usr/bin/dotnet /opt/dbmr-agent/AssessmentToolkit.Agent.dll`, and `Restart=always`. Do not put the PSK in a world-readable unit file.

---

## Discovery Agent user instructions

Complete these steps after registering and deploying a Discovery Agent.

### Configure database credentials

Use a dedicated read-only database account. The preferred production approach is to keep credentials on the Discovery Agent host instead of entering them for every portal job.

1. In **DB Inventory**, identify the database to assess. Retrieve its `databaseId` from `GET /api/databases?projectId=<project-guid>`; for a local portal, use `http://localhost:5000/api/databases?projectId=<project-guid>`.
2. On the Discovery Agent host, create `databases.json`:

```json
{
  "databases": [
    {
      "databaseId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
      "pluginId": "postgresql",
      "host": "db.internal",
      "port": 5432,
      "database": "applicationdb",
      "username": "assessment_reader",
      "password": "replace-with-secret"
    }
  ]
}
```

3. Mount the file read-only when starting the agent:

```bash
docker run -d \
  --name dbmr-agent \
  --restart unless-stopped \
  -v $(pwd)/bootstrap.json:/app/bootstrap.json:ro \
  -v $(pwd)/databases.json:/app/databases.json:ro \
  dbmigrationready-agent:latest
```

The `databaseId` must match the selected portal inventory record. Environment variables can be used instead of a file:

```text
AGENT_DB_0_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
AGENT_DB_0_PLUGIN=postgresql
AGENT_DB_0_HOST=db.internal
AGENT_DB_0_PORT=5432
AGENT_DB_0_NAME=applicationdb
AGENT_DB_0_USER=assessment_reader
AGENT_DB_0_PASSWORD=replace-with-secret
```

Add more profiles with `AGENT_DB_1_*`, `AGENT_DB_2_*`, and so on. Numbering must be contiguous from zero. Environment profiles override file entries with the same database ID.

For a one-time assessment, credentials can instead be entered in the **Dispatch Job** dialog. They are sent to the Discovery Agent in the job payload; use TLS and a dedicated read-only account.

### Start and verify the Discovery Agent

```bash
docker start dbmr-agent
docker logs -f dbmr-agent
```

A successful startup logs the agent ID, backend URL, and number of local database profiles loaded. Within about 30 seconds, the portal **Discovery Agents** page should show a recent heartbeat and move the Discovery Agent to an active state.

### Dispatch an assessment

1. Open **Discovery Agents** and select the project.
2. Confirm the Discovery Agent has a recent heartbeat and the required plugin is listed.
3. Select **Dispatch Job**.
4. Choose a database from inventory to use its matching local credential profile, or enter the host, port, database/service name, username, and password manually.
5. Confirm the plugin matches the database engine, then select **Dispatch**.
6. Open **Job History**. The job progresses from pending/assigned to running and then completed or failed. Discovery Agents poll every 30 seconds, so pickup is not immediate.

### View findings

In **Job History**, select the finding count for a completed job. The portal shows raw plugin findings and, when AI is configured, migration-path enrichment, risks, complexity, and remediation steps.

### Troubleshooting

| Symptom | Check |
|---------|-------|
| Agent exits immediately | Verify `AGENT_ID`, `AGENT_PSK`, and `AGENT_BACKEND_URL`, or validate the mounted `bootstrap.json`. |
| Agent remains registered/offline | Check `docker logs`, DNS/TLS access to the API, host clock synchronization, and outbound TCP/443. |
| Job stays pending | Confirm the agent is running, its heartbeat is current, and the job plugin is in the agent's allowed plugin list. |
| Authentication fails | Use the PSK from the one-time bootstrap package and synchronize the agent clock; signed requests allow a five-minute skew. |
| Database connection fails | Test name resolution and the database port from the agent host; verify the read-only account and database/service name. |
| Local credentials are ignored | Ensure the job uses an inventory database and its `databaseId` exactly matches the local profile. Restart after changing local files or environment variables. |
| Plugin is skipped | Enable one of the implemented plugin IDs and restart the agent: `postgresql`, `oracle`, `sqlserver`, or `mysql`. |

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

### SQL Server

```sql
USE [your_database];
CREATE USER [assessment_reader] FOR LOGIN [assessment_reader];
GRANT CONNECT TO [assessment_reader];
GRANT VIEW DATABASE STATE TO [assessment_reader];
GRANT VIEW DEFINITION TO [assessment_reader];
GRANT SELECT TO [assessment_reader];
```

Create the login at the server level using your organization's password and identity policy. Grant only the target databases required for assessment.

### MySQL / MariaDB

```sql
CREATE USER 'assessment_reader'@'agent-host-or-subnet'
  IDENTIFIED BY 'strong-password-here';
GRANT SELECT, REPLICATION CLIENT, PROCESS ON *.*
  TO 'assessment_reader'@'agent-host-or-subnet';
```

Restrict the account host to the agent host or subnet. `SELECT` provides metadata access; `REPLICATION CLIENT` and `PROCESS` enable replication and connection findings.

---

## Enabling AI features

AI enrichment and report generation use **Azure OpenAI** (or any Azure AI Foundry deployment). Without AI configuration the portal works fully — AI features simply show a warning banner.

### Option A — Environment variables (recommended for production)

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
2. Enter the Azure OpenAI endpoint, deployment name, and API key under **Active Connection**.
3. Select **Save Configuration**. The key is encrypted with ASP.NET Core Data Protection before it is stored and is never returned to the browser.
4. Select **Test Connection** to verify that the configured deployment can answer a model request.

Saving configuration and proving connectivity are separate states:

| Status | Meaning |
|--------|---------|
| `Not configured` | Endpoint or credential is missing. |
| `Not tested` / `Configured` | Configuration loaded, but no successful model request has been made since startup or the last configuration change. |
| `Connected` | The latest explicit connection test returned a model response. |
| `Connection failed` / `Error` | The latest test could not get a model response. Check endpoint, deployment, key, and network access. |

For Docker Compose, the Data Protection key ring is persisted in the `data_protection_keys` named volume. If deploying the API another way, set `DataProtection__KeysPath` to durable storage shared across API restarts. Back up that key ring with the database; without it, stored API credentials cannot be decrypted.

### Verifying AI is active

```bash
curl http://localhost:5000/api/ai/status
# {"available":true,"connectionStatus":"Not tested","message":"Configuration loaded. Test the connection to verify model access.",...}
```

Use **Test Connection** in AI Settings or call:

```bash
curl -X POST http://localhost:5000/api/ai/test
# {"succeeded":true,"message":"Connection successful.","testedAt":"..."}
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
| `DataProtection__KeysPath` | Durable ASP.NET Core key-ring directory used to protect portal-entered credentials | Platform default |
| `AiFoundry__Endpoint` | Azure OpenAI endpoint URL | — |
| `AiFoundry__Deployment` | Model deployment name (e.g. `gpt-4o`) | — |
| `AZURE_OPENAI_API_KEY` | Azure OpenAI API key; alternative to the encrypted portal credential | — |

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
| `AGENT_PLUGINS` | Comma-separated plugin IDs: `postgresql`, `oracle`, `sqlserver`, `mysql` |
| `AGENT_BOOTSTRAP_PATH` | Path to `bootstrap.json` (alternative to env vars) |
| `AGENT_DATABASES_PATH` | Path to local database credential profiles (default: `databases.json`) |
| `AGENT_DB_n_ID` | Inventory database GUID for local profile index `n`, starting at zero |
| `AGENT_DB_n_PLUGIN` | Plugin ID for local profile `n` |
| `AGENT_DB_n_HOST`, `AGENT_DB_n_PORT`, `AGENT_DB_n_NAME` | Connection target for local profile `n` |
| `AGENT_DB_n_USER`, `AGENT_DB_n_PASSWORD` | Read-only credentials for local profile `n` |

---

## Security notes

- All agent-to-backend communication is authenticated with **HMAC-SHA256** (method + path + timestamp + body hash).
- Timestamps are validated within a ±5 minute window to prevent replay attacks.
- PSKs are stored as **salted SHA-256 hashes** in the database — the raw value is shown once at registration and never recoverable.
- AI API keys entered in the portal are encrypted at rest with ASP.NET Core Data Protection, never returned by the API, and require a persistent protected key ring for recovery after restart.
- Use TLS in production — the portal API should be served behind HTTPS; the agent verifies the server certificate.
- The evidence storage volume should be backed up regularly; it holds uploaded AWR and Statspack files.

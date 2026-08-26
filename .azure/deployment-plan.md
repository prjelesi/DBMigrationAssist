# Azure Deployment Plan

> **Status:** Validated

## 1. Goal

Restore the Azure Platform Local Agent by deploying the existing discovery-agent image as an always-on Azure Container App so it can heartbeat, claim pending jobs, and reach databases through the existing VNet integration.

**Path:** Modify existing deployment
**Classification:** Development
**Scale:** Small
**Budget:** Cost-optimized
**Subscription:** `7ee7fa4f-8359-4fb9-ac34-361728102038`
**Location:** `swedencentral`

## 2. Components

| Component | Technology | Azure service |
|-----------|------------|---------------|
| Discovery agent | .NET 8 container | Azure Container Apps |
| Bootstrap storage | Azure Files | Existing Container Apps environment storage |
| Image registry | Azure Container Registry | Existing registry with managed identity pull |

## 3. Recipe

**Selected:** Bicep through the repository's `infra/deploy.ps1` workflow.

The deployment reuses the existing VNet-integrated Container Apps environment, user-assigned managed identity, ACR, and `local-agent` Azure Files share. The agent has no ingress and runs one replica with `0.5` vCPU and `1 GiB` memory.

## 4. Resource Inventory And Capacity

| Resource type | Number to deploy | Capacity result |
|---------------|------------------|-----------------|
| `Microsoft.App/containerApps` | 1 | Uses the existing managed environment; environment usage is 1 of 50 in Sweden Central |

**Status:** Capacity available. No new managed environment or GPU quota is required.

## 5. Security And Operations

- Pull the private ACR image with the existing user-assigned managed identity.
- Mount the existing bootstrap share; do not put the agent PSK in Bicep or environment variables.
- Expose no ingress.
- Keep one replica active for heartbeats and job polling.
- Preserve existing API, worker, frontend, PostgreSQL, storage, Key Vault, and networking resources.
- Do not modify or validate VNet peering per user instruction.

## 6. Execution Checklist

- [x] Analyze the current Azure deployment and agent runtime
- [x] Confirm subscription and location from the approved deployment configuration
- [x] Check Container Apps capacity
- [x] Add the discovery-agent Container App Bicep module
- [x] Wire the discovery-agent image into the deployment script
- [x] Compile the Bicep template
- [x] Validate PowerShell syntax and `git diff --check`
- [x] Build and smoke-test the discovery-agent image locally
- [x] Run Azure subscription deployment What-If
- [x] Record validation proof and set status to `Validated`
- [x] Deploy after validation
- [x] Verify Container App state, logs, heartbeat, and pending-job processing

## 7. Validation Proof

| Check | Command | Result |
|-------|---------|--------|
| Bicep compilation | `az bicep build --file infra/main.bicep --stdout` | Pass |
| Deployment prerequisites | `infra/deploy.ps1 -Mode Validate` | Pass |
| PowerShell syntax | Parse `infra/deploy.ps1` | Pass |
| Patch whitespace | `git diff --check` | Pass |
| Agent image build | `docker compose build local-agent` | Pass |
| Agent runtime smoke test | Run image entrypoint with `dotnet --info` | Pass |
| Container Apps capacity | Azure quota check in Sweden Central | Pass; existing environment usage 1 of 50 |
| Azure deployment preview | `infra/deploy.ps1 -Mode WhatIf` | Pass; no resources created |
| Azure deployment | `az deployment sub create --name dbmigrationready-1fa1-agent-20260821102502` | Pass |
| Agent runtime | Container App revision and replica inspection | Pass; revision `0000001` running with one replica |
| Agent polling | Container logs | Pass; Oracle and MongoDB jobs claimed |
| Application release build | `build.ps1` | Pass on 2026-08-21; API, worker, agent, and frontend published with no warnings or errors |
| Local image build | `docker compose build api worker frontend local-agent` | Pass on 2026-08-21; all four deployment images built |
| Local runtime smoke test | API `/health` and portal `/` | Pass on 2026-08-21; both returned HTTP 200 |
| Existing Container Apps environment | `az containerapp env list` | Pass on 2026-08-21; `cae-dbmigratio-dev-1fa1` is `Succeeded` |
| Registry pull role | `az role assignment list` | Pass on 2026-08-21; managed identity has `AcrPull` on the existing ACR |
| Azure deployment preview | `infra/deploy.ps1 -Mode WhatIf` | Pass on 2026-08-21; no deletions or replacements proposed |

**Validated by:** azure-validate workflow

## 8. Files

| File | Purpose |
|------|---------|
| `.azure/deployment-plan.md` | Deployment and validation record |
| `infra/main.bicep` | Wires the agent module into the subscription deployment |
| `infra/modules/agent-container-app.bicep` | Defines the non-ingress discovery-agent Container App |
| `infra/deploy.ps1` | Passes the pushed discovery-agent image to Bicep |

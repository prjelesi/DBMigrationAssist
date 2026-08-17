# Project Plan Delta Report

_Comparison of `project-plan.html` v1.0 (2026-07-24) with the current DB Migration Assessment Toolkit implementation._

## 1. Executive summary

The original plan remains useful as a historical product baseline, but it no longer describes the implemented architecture or full product scope. The implementation retained the central objective: inventory databases, collect technical evidence, capture questionnaire context, and generate migration guidance. It then evolved from a relatively small FastAPI assessment service into a .NET-based, project-oriented assessment toolkit with a background worker, richer discovery, portfolio planning, communication maps, and connected, standalone, and air-gapped operating modes.

The most significant deliberate substitutions are ASP.NET Core for FastAPI, HMAC-signed agent polling for direct PSK-header calls, PostgreSQL/local-volume persistence for the planned Blob/Key Vault model, and Container Apps hosting for both the portal and APIs rather than Static Web Apps plus an API container. The largest capability additions are customers/projects, persistent platform-local agents, database-bound offline collectors, versioned questionnaires, evidence management, portfolio waves, communication maps, and report review states.

The implementation is a strong PoC/MVP expansion, but it is not yet the production-hardened platform described by Phase 4 of the plan. Entra ID authentication, RBAC and immutable audit, Key Vault and managed identity, Blob/object-storage abstraction, full connected support for seven engines, PDF/shareable report export, comprehensive tests, CI/CD, private networking, and complete operational monitoring remain open or partial.

## 2. Planned versus implemented

| Area | Original plan | Current implementation | Assessment |
| --- | --- | --- | --- |
| Backend | Python 3.12, FastAPI, Pydantic, SQLAlchemy and Alembic | .NET 8, ASP.NET Core controllers, EF Core and Npgsql | Deliberate architecture substitution, recorded in the architecture decisions. |
| Agent runtime | Python agent with seven collectors | .NET 8 worker agent with PostgreSQL, Oracle, SQL Server, MySQL/MariaDB, MongoDB, Cassandra and SAP/Sybase ASE plugins | Planned connected-engine breadth is implemented with a common plugin contract. |
| API contract | Versioned `/api/v1` portal and agent endpoints | REST endpoints primarily under `/api`; agents poll jobs and submit results | Contract and lifecycle changed materially; OpenAPI/Swagger remains available. |
| Portal identity | Entra ID OIDC/JWT | Portal APIs currently operate without broad Entra authentication or authorization middleware | Deferred production control. |
| Agent authentication | Raw PSK in `X-Agent-Key` | Per-agent PSK-derived HMAC-SHA256 signatures over method, path, timestamp and body hash | Security improvement; reduces replay and credential disclosure risk. |
| Agent lifecycle | Self-register, pull config, heartbeat and submit report | Portal registration/bootstrap, outbound job polling, heartbeat, dispatch and signed result submission | More operator-controlled and project-scoped than planned. |
| Secret storage | Key Vault references for PSKs, database credentials and AI keys | Salted/hashed agent PSKs; local agent credential profiles; encrypted portal-entered AI keys; Container App secrets | Appropriate for PoC/local modes, but Key Vault/managed identity integration is not delivered. |
| Frontend hosting | Azure Static Web Apps | nginx container locally and frontend Container App in Azure Bicep | Simpler shared container deployment model. |
| Background processing | Mostly API orchestration | Dedicated Worker for timeouts, health and result enrichment | Added separation of responsibilities and scaling path. |
| Metadata | Environments, databases, agents, assessments and reports | Customers, projects, project environments, databases, agents, jobs/results, questionnaires, evidence, graph and portfolio entities | Domain model expanded from assessment runs to an estate workspace. |
| Inventory import | CSV | Excel workbook import plus manual database creation | User workflow changed and expanded. |
| Connected discovery | Six named collectors plus MariaDB support | Seven executable plugin families, with engine-specific metadata and resilient optional sections | Planned breadth delivered; live database validation remains uneven across engines. |
| Air-gapped workflow | Upload a pre-collected JSON report | Generate a database-bound PowerShell collector, execute with native tools, transfer JSON, validate and upload against that database | Major functional and trust-model improvement. Offline scripts cover seven engine families. |
| Assessment result shape | Single general report schema | Versioned plugin findings, signed connected bundles, and structured `offline-2.0` sections with independent failure status | More resilient and diagnostically useful than planned. |
| Questionnaire | JSON-defined multi-step questionnaire | Versioned baseline and engine-specific templates, conditional/custom answers and evidence attachments | Delivered and expanded. |
| AI providers | Azure OpenAI or Foundry Copilot selected per report | Microsoft Foundry/Azure OpenAI-compatible configuration with explicit readiness/connectivity checks | Provider administration is stronger; reporting currently requires AI readiness. |
| Rules fallback | Deterministic report when AI is absent or fails | No first-class rules-only report fallback in the current reporting gate | Planned resilience was not retained. |
| Report workflow | Generate, view, download PDF/JSON | Generate structured reports, progress through Draft Ready/In Review/Approved/Exported, and download JSON | Review states added; PDF and expiring share links remain missing. |
| Evidence storage | Blob Storage for reports and uploads | Configured local evidence volume with SHA-256 metadata; assessment result JSON in PostgreSQL | Supports local/isolated deployment; cloud storage abstraction remains incomplete. |
| Azure topology | Static Web App, API Container App, ACR, PostgreSQL, Storage, Key Vault, OpenAI, Monitor and App Insights | Bicep creates API, Worker and frontend Container Apps, PostgreSQL Flexible Server and Log Analytics | Core runtime is deployable; several planned managed services and controls are absent. |
| Testing and delivery | pytest, Playwright, seven-engine E2E and GitHub Actions | Solution build validation and a PostgreSQL agent E2E PowerShell test; no repository workflow | Well short of Phase 4 quality and automation scope. |

## 3. Capabilities added beyond the plan

### Project and estate management

- Customer records and project workspaces replace the original environment-first navigation model.
- Projects explicitly support Connected, Air-Gapped and Standalone deployment modes.
- Discovery Agents are shown across projects in a filterable table rather than only through a selected project.
- Communication maps model database dependencies, and portfolio views group databases into migration waves.

### Local and disconnected operation

- A persistent platform-local agent can assess databases using locally maintained credential profiles without creating one agent container per project.
- The portal generates engine-specific PowerShell collectors bound to a database record.
- Offline upload validates schema version, plugin identity, database identity, JSON structure and a 10 MB size limit.
- Offline results are explicitly marked unsigned and unverified. This is a clearer trust boundary than the original generic manual-upload story.
- Native client credential handling avoids passwords in command-line arguments where practical, and Cassandra uses a restricted temporary credentials file.

### Discovery depth and resilience

- PostgreSQL adds primary-key, data-type, JSON, partition, foreign-key, tablespace and collation compatibility signals.
- Oracle adds wrapped source, unsupported objects, LOB sizing and redo-volume evidence.
- MySQL/MariaDB adds engine, foreign-key mismatch, ENUM/invisible column, partition, authentication-plugin and buffer-pool signals.
- Optional metadata sections fail independently, preserving baseline findings when permissions or vendor/version differences block one query.

### Operational workflow

- The Worker monitors agent health and job timeouts and enriches completed findings.
- Report readiness distinguishes configured AI from a successfully tested provider connection.
- Report lifecycle states support review and approval progression, which was only lightly specified in the original plan.

## 4. Reduced, deferred or changed scope

### Security and governance

The current PoC does not yet implement portal Entra ID authentication, project/environment RBAC, immutable audit records, production rate limiting, or the complete Key Vault/managed-identity model. HMAC agent authentication is stronger than the original direct-header scheme, but key rotation grace and acknowledgement should be verified before claiming full parity with the later architecture specification.

### Database coverage

Connected discovery and generated offline collection now both cover PostgreSQL, Oracle, SQL Server, MySQL/MariaDB, MongoDB, Cassandra and SAP/Sybase ASE. The newer MongoDB, Cassandra and Sybase connected collectors compile and follow the shared read-only result contract, but still require representative live-version integration testing before production certification.

### Reporting

The implementation has structured AI reports, JSON download and review-state transitions. It does not yet provide the planned PDF export, expiring share link, section-level comments/locking, or a deterministic rules-only fallback. Requiring Microsoft Foundry readiness creates a connected-service dependency that conflicts with the architecture principle that core air-gapped workflows should not require internet access.

### Storage and Azure infrastructure

Uploaded evidence uses a configured filesystem volume, and structured results live in PostgreSQL JSONB. The Azure template does not currently provision Blob Storage, Key Vault, Application Insights or an AI resource, and it does not implement the planned private endpoints/VNet restrictions. This is suitable for demo deployment but not equivalent to the planned production topology.

### Quality and operations

The repository has one PostgreSQL agent E2E script and has been validated by successful .NET builds, but the planned all-engine integration suite, portal Playwright coverage, CI/CD pipeline, security test evidence, backup/restore runbook, alerts and operational dashboards are not complete.

## 5. Impact of the changes

### Positive impact

- A single .NET stack across API, Worker and Agent simplifies shared contracts and HMAC implementation.
- Project-scoped polling and signed requests provide a stronger agent security model.
- The offline collector workflow makes disconnected assessments repeatable and auditable at the database-record level.
- Section-level discovery failures improve reliability in real customer estates with restricted metadata permissions.
- Portfolio, graph, evidence and richer questionnaire functions move the product closer to an end-to-end migration discovery toolkit.

### Trade-offs and risks

- The broader functional scope arrived before the planned identity, RBAC, audit and automated-test controls.
- Local-volume evidence and Container App secrets require additional design before multi-instance or production use.
- Different connected and offline engine support matrices can create expectation and documentation risk.
- Foundry-required report generation weakens the stated offline-first architecture unless a local or deterministic report path is restored.
- The historical HTML plan, architecture document, MVP backlog and current implementation now describe different maturity levels and should not all be treated as authoritative current state.

## 6. Recommended plan reconciliation

1. Mark `project-plan.html` as the historical v1 baseline and designate the Solution Architecture Document plus this delta report as the current architecture record.
2. Publish an explicit capability matrix separating connected agent, platform-local agent and generated offline collector support by engine.
3. Prioritize production controls: Entra ID, authorization/RBAC, audit events, Key Vault/managed identity, replay protection verification and rate limiting.
4. Decide the reporting contract: restore deterministic/local fallback for disconnected modes or formally make connected Foundry a prerequisite.
5. Complete report delivery with PDF export, review comments/section locking and controlled share/export behavior.
6. Introduce storage interfaces for local volume, Azure Blob/Files and future SharePoint publishing, with retention and backup policies.
7. Expand tests from PostgreSQL E2E to all advertised connected plugins, offline envelope validation, HMAC negative/replay cases, API integration and Playwright user journeys.
8. Add CI/CD and deployment validation for the .NET, frontend, container and Bicep artifacts.
9. Update Azure Bicep for production topology only after the security, storage and identity decisions are confirmed.

## 7. Evidence reviewed

- Original baseline: [`../project-plan.html`](../project-plan.html)
- Current architecture decisions: [`Solution_Architecture_Document.md`](Solution_Architecture_Document.md)
- MVP release expectations: [`MVP_Backlog.md`](MVP_Backlog.md)
- Runtime and operator guidance: [`../README.md`](../README.md) and [`../demo/DEMO_GUIDE.md`](../demo/DEMO_GUIDE.md)
- Azure deployment: [`../infra/main.bicep`](../infra/main.bicep)
- Agent plugins and registration: [`../src/agent/AssessmentToolkit.Agent/Plugins`](../src/agent/AssessmentToolkit.Agent/Plugins) and [`../src/agent/AssessmentToolkit.Agent/Program.cs`](../src/agent/AssessmentToolkit.Agent/Program.cs)
- API security and offline collection: [`../src/backend/AssessmentToolkit.Api/Middleware/AgentHmacAuthMiddleware.cs`](../src/backend/AssessmentToolkit.Api/Middleware/AgentHmacAuthMiddleware.cs) and [`../src/backend/AssessmentToolkit.Api/Services/OfflineAssessmentScriptFactory.cs`](../src/backend/AssessmentToolkit.Api/Services/OfflineAssessmentScriptFactory.cs)
- Domain and evidence model: [`../src/backend/AssessmentToolkit.Core/Entities`](../src/backend/AssessmentToolkit.Core/Entities)
- Portal workflows: [`../src/frontend/src/pages`](../src/frontend/src/pages)
- Existing E2E test: [`../tests/AgentPostgresE2E.ps1`](../tests/AgentPostgresE2E.ps1)
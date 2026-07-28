# Solution Architecture Document

_Assessment Toolkit | Architecture, deployment, security and integration design_

> **Baseline:** The Assessment Toolkit is a containerised database migration assessment and planning platform for customer database estates. It includes a unified assessment portal, Docker-based assessment agents, questionnaire and evidence collection, file/report storage, AI-assisted or rules-based reporting, portfolio grouping, communication maps, and Factory-aligned migration planning.

## 1. Purpose and scope

This document defines the target solution architecture for the Assessment Toolkit. It translates the project plan into an implementation-ready architecture covering logical components, container deployment, agent communication, storage, AI integration, security controls and operational flows.

## 2. Architecture principles

- **Container first:** all major runtime services must run as containers.
- **Air-gapped capable:** core workflows must not depend on mandatory internet access.
- **Evidence traceability:** reports must link back to questionnaires, uploaded files, assessment results and rule decisions.
- **Least privilege:** project, environment, agent and file access must be scoped through RBAC and audit.
- **Pluggable assessment model:** database-specific discovery logic must be implemented through plugins.

## 3. Logical architecture

| Layer | Responsibilities | Key components |
| --- | --- | --- |
| Experience layer | Human-facing project workspace and review experience | Frontend web app, dashboard, questionnaires, portfolio view, communication map viewer, report review UI |
| API and orchestration layer | Business APIs, workflow coordination, identity, RBAC and audit | Backend API, orchestration service, job scheduler, rules engine, graph service, report workflow |
| Data layer | Metadata, graph relationships, results and audit | PostgreSQL metadata database, graph tables, JSONB evidence store, audit tables |
| Storage layer | Binary and semi-structured evidence and deliverables | Local persistent volume, SMB/NFS share, Azure Files, object storage, SharePoint/OneDrive connector |
| Agent layer | Customer estate discovery and assessment | Docker agent runtime, plugin executor, local queue, secure outbound submission |
| AI/reporting layer | Narrative generation and rules-based fallback | AI provider registry, AI Foundry connector, local model connector, rules-based report generator |

## 4. Container deployment model

| Container | Primary function | Stateful? | Notes |
| --- | --- | --- | --- |
| frontend | Portal UI for projects, questionnaires, portfolios, maps and report review | No | Can be served through reverse proxy or ingress. |
| api | REST/GraphQL API, RBAC, project model and validation | No | Uses metadata database and storage abstraction. |
| worker | Background jobs for parsing, rules, graph generation and reports | No | Scales horizontally for larger estates. |
| postgres | Metadata and graph persistence | Yes | Can be embedded for isolated deployments or replaced with customer-managed PostgreSQL. |
| storage-adapter | File operations, checksums, retention metadata and export links | Depends | Abstracts local, file share and connected storage modes. |
| ai-adapter | AI Foundry/private/local model routing and rules-only fallback | No | Disabled by default in strict air-gapped mode. |

## 5. Agent communication pattern

1. Administrator creates an agent registration record for a project/environment and specifies the allowed plugin scope.
2. During registration the administrator chooses one of two PSK modes:
   - **System-generated (default):** the portal generates a cryptographically random PSK (minimum 256-bit / 32 bytes) and includes it in the bootstrap package. The raw PSK value is shown once at download time and is not stored in recoverable form.
   - **User-supplied:** the administrator provides their own PSK value. The system validates that it meets the minimum entropy requirement (≥ 32 bytes, no common or repeated patterns) and rejects values that fall below the threshold. The supplied value is stored as a salted hash; only the hash is retained server-side.
3. System assembles a scoped bootstrap package containing: the backend HTTPS address, the agent identifier, the allowed plugin list, and the PSK (system-generated or confirmed user-supplied).
4. The bootstrap package is the only configuration the agent requires at startup. It is delivered out-of-band (download from portal, secure copy or secrets injection at container launch).
4. All agent-to-backend HTTP communication uses TLS. Every request carries an `X-Agent-Signature` header containing an **HMAC-SHA256** value derived from the PSK over the request method, path, timestamp and body hash. The backend rejects requests with a missing, invalid or replayed signature.
5. The agent polls for jobs using its scoped identifier and PSK-signed requests, using outbound-only connectivity wherever the customer network permits.
6. The agent runs assigned plugins, writes local evidence files, then assembles a signed result bundle. The bundle manifest includes a PSK-derived HMAC over the full payload.
7. The backend validates the HMAC signature, checks the agent identifier is active and in-scope, and verifies the payload checksum before accepting the result for normalisation and graph correlation.
8. **PSK rotation:** the administrator generates a new bootstrap package from the portal. The agent accepts a grace-period overlap during which both keys are valid. The old PSK is revoked once the agent acknowledges the new key or after a configured rotation window.

## 6. Integration architecture

| Integration | Mode | Primary use |
| --- | --- | --- |
| SharePoint/OneDrive | Connected or hybrid | Approved report publishing and document library storage. |
| SMB/NFS/Azure Files | Air-gapped, hybrid or connected | Evidence storage, raw output retention and customer-managed file locations. |
| AI Foundry | Connected or private/customer-managed | Assessment narrative, risk register, wave plan and executive summary generation. |
| Local model endpoint | Air-gapped optional | Customer-approved offline model endpoint for narrative generation. |
| Rules engine | All modes | Deterministic classification and fallback report generation. |

## 7. Security architecture

- Use project-level and environment-level RBAC boundaries.
- Store agent secrets only in secure configuration; never include secrets in logs or result files.
- Require TLS for all agent-to-backend and service-to-service communication.
- **Agent authentication uses a per-agent pre-shared key (PSK).** Every agent API call and result bundle must carry an HMAC-SHA256 signature derived from the PSK. The backend rejects submissions with a missing, invalid, expired or replayed signature. PSKs must never appear in logs, result files or error responses.
- Enforce a replay-prevention window: requests with a timestamp outside ±5 minutes of server time are rejected.
- Separate raw evidence from reviewed deliverables; raw evidence is not directly accessible through the reporting or export path.
- Maintain immutable audit records for agent registrations, PSK issuance and rotation, uploads, parsing, AI submissions, approvals and exports.
- Disable external AI calls unless explicitly configured and enabled for the deployment mode.

## 8. Reporting workflow

The reporting workflow is a distinct orchestrated phase triggered once evidence collection reaches a sufficient completeness threshold. It coordinates questionnaire data, assessment results and AI generation into a reviewable, approvable deliverable.

1. **Evidence readiness gate:** The worker confirms that assessment jobs for in-scope databases are complete and that a minimum evidence confidence threshold is met. Incomplete or low-confidence items are surfaced for review before proceeding.
2. **Supplemental questionnaire:** The system activates the reporting-phase questionnaire section, collecting additional context not captured during technical discovery: migration goals and constraints, acceptable downtime windows, target platform preferences, risk tolerance and stakeholder contacts.
3. **Evidence bundle assembly:** The worker assembles a versioned evidence bundle comprising: completed questionnaire responses (baseline and supplemental), normalised assessment findings, communication map state, portfolio grouping and references to uploaded reports.
4. **AI submission:** The bundle is submitted to the registered AI agent (AI Foundry GPT model or Copilot-hosted endpoint) with a structured prompt specifying the required report sections, output format and any customer-specific constraints.
5. **Draft generation:** The AI agent returns a structured draft report. Each section is tagged with the evidence items used to produce it, maintaining traceability back to source data.
6. **Rules-based fallback:** If no AI agent is configured or the AI call fails, the rules engine generates a deterministic draft using migration-path classification rules and predefined templates.
7. **Review and approval:** The draft is routed to the designated reviewer. Reviewers can comment on, override or reject individual sections. Approved sections are locked from further AI regeneration.
8. **Export:** The finalised report is exported to the configured storage target (local volume, file share, Azure Files or SharePoint/OneDrive) and an immutable audit record is created.

| Report state | Description |
| --- | --- |
| Pending | Evidence readiness gate not yet passed. |
| Questionnaire active | Supplemental questionnaire is open for input. |
| Bundle ready | Evidence bundle assembled; awaiting AI submission. |
| AI generating | AI submission is in progress. |
| Draft ready | Draft available for reviewer. |
| In review | Active review in progress; comments open. |
| Approved | All sections approved; export available. |
| Exported | Report delivered to configured storage target. |

## 9. Operational concerns

| Concern | Design requirement |
| --- | --- |
| Backup and restore | Metadata database and file storage must have documented backup/restore procedures per deployment mode. |
| Observability | API, worker and agent events must produce structured logs and health metrics. |
| Upgrade | Air-gapped deployments must support signed offline bundles and versioned database migrations. |
| Scale | Large estates must support worker fan-out, queued ingestion and incremental graph refresh. |
| Data retention | Retention and deletion policies must apply separately to raw evidence, generated drafts and approved deliverables. |

## 10. Architecture decisions

The following decisions were confirmed during PoC planning (2026-07-27):

| Decision | Resolution | Rationale |
| --- | --- | --- |
| Backend framework | **ASP.NET Core (.NET / C#)** | First-class Azure Container Apps support; shared PSK/HMAC signing library reused by agent runtime; EF Core + Npgsql for PostgreSQL; OpenAPI via Swashbuckle. |
| API pattern | **REST** with OpenAPI spec | Simpler to consume from agent runtime and external integrations; GraphQL deferred to post-MVP if query flexibility is needed. |
| Frontend framework | **React (TypeScript)** | Best ecosystem for graph/communication-map visualisation (React Flow, Cytoscape.js); suits data-heavy dashboard and questionnaire UIs. |
| Graph visualisation library | **React Flow** (primary); D3.js for complex layouts | React Flow handles interactive node-edge graphs with built-in minimap and zoom; D3 available for custom force-directed layouts. |
| PostgreSQL deployment | **Embedded for MVP**; customer-managed PostgreSQL supported via connection string override | Simplifies PoC and isolated deployments; Npgsql connection string abstraction makes swap transparent. |
| PoC deployment target | **Azure Container Apps** | Customer already has demo environment with all database types deployed on ACA. |
| Initial database plugins | **Oracle** and **PostgreSQL** | Covers the highest-priority source engines from the Factory service description. SQL Server to follow in R2. |
| SharePoint/OneDrive publishing | **Should-have (post-MVP)** | Export to Azure Files / local volume is sufficient for PoC; SharePoint connector deferred to R4. |

# System Overview

**Reviewed:** 2026-09-23

**Scope:** Implemented behavior in the repository at the documented baseline.

## Purpose

The Database Migration Assessment Toolkit is a project-oriented workspace for collecting database inventory, technical assessment findings and business context, then producing evidence-grounded migration reports.

The current system supports connected agents, generated offline collectors, manual inventory, questionnaire responses, uploaded evidence, database communication maps, portfolios and persisted AI-generated reports.

## Runtime services

| Service | Implementation | Responsibility |
|---|---|---|
| Portal | React, TypeScript, Vite, Fluent UI, React Query | Operator workspace and report review experience. |
| API | ASP.NET Core .NET 8 | Authentication, authorization, REST APIs, persistence and report orchestration. |
| Worker | .NET 8 hosted services | Health reporting, stale-agent handling, job timeouts and result enrichment. |
| Assessment agent | .NET 8 worker process | Outbound polling, database plugin execution and signed result submission. |
| Database | PostgreSQL with EF Core and Npgsql | Durable application, evidence metadata, governance and reporting state. |

## Implemented workflows

### Sign in and project access

- Users sign in with application-managed email and password credentials.
- The API issues an HTTP-only session cookie with an eight-hour sliding lifetime.
- Portal mutations require an antiforgery token.
- Platform roles are `Administrator` and `User`.
- Project memberships are `Viewer`, `Contributor` or `Owner`, with optional environment scope.
- Administrators can access all projects. Standard users see projects for which they have membership.
- Creating a project gives its creator an `Owner` membership.

Project-list visibility is membership-filtered. Global system configuration, agent overview, AI provider/configuration, connection testing and report-instruction endpoints require the `Administrator` role. Object-level authorization remains incomplete for the routes identified in [Known Limitations](KNOWN_LIMITATIONS.md).

### Workspace and inventory

- Create and list customers, projects and environments.
- Create, list, update and bulk-import database inventory.
- Download an Excel inventory template and import a completed workbook atomically.
- Download a database-specific PowerShell collector.
- Upload validated offline assessment JSON for a database.
- Offline uploads are persisted as completed assessment jobs without an agent and with `Unverified` confidence.

### Connected assessment

- Register project-scoped agents and obtain bootstrap material.
- Agents heartbeat, poll for jobs and submit results over outbound HTTP.
- Agent requests use HMAC-SHA256 authentication with per-agent pre-shared keys.
- Dispatch jobs against inventory databases or ad hoc connection details.
- View job history, findings and AI enrichment in the portal.
- A platform-managed local agent and `Local Assessments` project are provisioned when configured.

Plugin implementations are registered for:

| Plugin | Source implementation | Repository integration evidence |
|---|---|---|
| PostgreSQL | Implemented | Covered by `tests/AgentPostgresE2E.ps1`. |
| Oracle | Implemented | Requires representative live-version certification. |
| SQL Server | Implemented | Requires representative live-version certification. |
| MySQL/MariaDB | Implemented | Requires representative live-version certification. |
| MongoDB | Implemented | Requires representative live-version certification. |
| Cassandra | Implemented | Requires representative live-version certification. |
| SAP/Sybase ASE | Implemented | Requires representative live-version certification. |

An implemented plugin is not the same as production certification for every engine/version combination.

### Questionnaires and evidence

- Load versioned questionnaire templates from JSON.
- Create and resume project-wide responses or responses scoped to a specific database in the project.
- Maintain one response per template at project scope and one response per template for each database scope.
- Save answers and enforce required fields before submission.
- Attach evidence to questionnaire responses and questions, retaining the selected database scope.
- Upload, list, download, delete and reparse evidence files.
- Persist file metadata, hashes, parser state and parser summaries.
- Deterministically extract database identity, snapshot period, host capacity, load profile and top timed events from database-scoped Oracle AWR text or HTML evidence.

### Portfolio and communication map

- Persist manual database-to-database communication edges.
- Store protocol, port, description and confidence on graph edges.
- Create and maintain portfolios containing selected database IDs.
- Visualize the current project graph in the portal.

This is a database-level manual model. Automatic topology discovery, application/service nodes and dependency-derived migration waves are not implemented.

### AI and reporting

- Configure and test a Microsoft Foundry/Azure OpenAI-compatible endpoint and deployment.
- Report generation is blocked until the configured model passes a real connection test.
- Build a bounded prompt from the latest successful assessment per database/plugin, uploaded evidence summaries, questionnaire answers, graph edges and portfolios.
- Supply Oracle-specific topology, sizing, compatibility, conversion-complexity and collection-gap summaries to report generation.
- Load external Markdown report instructions for every report and allow administrators to update writable policy from AI Settings with SHA-256 concurrency protection.
- Persist the complete source snapshot as an `EvidenceBundle` with a content hash.
- Record the effective report-instruction content, source and SHA-256 hash in each evidence bundle.
- Persist generated report JSON and its lifecycle state.
- Support controlled report transitions for review, approval and export.
- Restrict approval to project owners or administrators.
- Download report JSON from the browser.

There is no deterministic rules-only report fallback. PDF generation, expiring share links and server-side publishing are not implemented.

### Administration and governance

- Administrator APIs can list users, create users and activate/deactivate accounts.
- Project owners and administrators can list, add and remove project memberships.
- Project owners and administrators can permanently delete a project and its dependent inventory, assessments, questionnaires, evidence, reports, agents, environments and memberships.
- Successful non-authentication requests using methods other than GET, HEAD and OPTIONS are recorded as audit events; GET-side mutations are not.
- The System page exposes component status, system configuration and agent visibility.

User and membership management have backend APIs but no portal management screen. Password reset, user deletion, platform-role changes and self-service profiles are not implemented.

## Portal routes

| Route | Current behavior | Status |
|---|---|---|
| `/` | Dashboard summary and project selection. Some counts use the first accessible project rather than the whole estate. | Partial |
| `/system` | API/database/worker/AI status, system configuration and all-agent view. | Implemented |
| `/projects` | Customer and project workspace creation, selection and owner/admin deletion. | Implemented |
| `/environments` | Environment creation, editing and deletion. | Implemented |
| `/inventory` | Database CRUD, Excel import and offline collector workflow. | Implemented |
| `/agents` | Agent registration, bootstrap, jobs, dispatch and findings. | Implemented |
| `/questionnaire` | Project/database scope selection, template sync, drafts, validation, answers, submission and attachments. | Implemented |
| `/evidence` | Evidence upload, listing, download, deletion and reparsing. | Implemented |
| `/portfolio` | Manual portfolio grouping and persistence. | Implemented, manual grouping only |
| `/communication-map` | Manual database graph editing and visualization. | Implemented, database-level only |
| `/reports` | Persisted report generation, review transitions and JSON download. | Implemented with export limitations |
| `/ai-settings` | Provider registry, active model configuration, connectivity test and administrator report-instructions editor. | Implemented |

## Environment isolation

Local Docker Compose and Azure use independent PostgreSQL databases and independent file storage. Deploying the same container images does not synchronize projects, users, inventory, evidence or reports between environments.

The local `postgres_data` volume preserves local records across container recreation. Azure data persists in its PostgreSQL Flexible Server and mounted file shares.

## Verification baseline

The repository includes focused xUnit API/service tests, focused Vitest report tests and one end-to-end PostgreSQL agent test. The current implementation has also been validated through .NET builds, frontend build/lint, local Docker smoke tests and a deployment smoke test. The 2026-09-01 Azure deployment verified all four Container Apps on immutable tag `20260901214321`, PostgreSQL Flexible Server 17 readiness, and HTTP 200 responses from the portal and API health endpoint. These checks do not replace a complete automated regression, security or all-engine compatibility suite.
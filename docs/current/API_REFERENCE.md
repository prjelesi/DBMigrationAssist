# API Reference

**Reviewed:** 2026-08-20  
**Base path:** `/api`

This is a route inventory, not a replacement for generated OpenAPI. Swagger UI is enabled only when the API runs in the ASP.NET Core `Development` environment.

## Access conventions

- Portal API calls use the application session cookie.
- Portal writes also send `X-CSRF-TOKEN`, obtained from `GET /api/auth/antiforgery`.
- Agent-facing routes under `/api/agent/{agentId}` require HMAC headers.
- Worker enrichment uses `X-Worker-Token`.
- `GET /health` is anonymous and outside the `/api` base path.
- Role and project membership checks may further restrict authenticated requests.

Authentication does not imply administrator authorization. User administration is explicitly administrator-only, but system configuration and AI provider/configuration endpoints currently have no `Administrator` role annotation and are available to any authenticated portal user.

## Authentication

| Method | Route | Behavior |
|---|---|---|
| `GET` | `/api/auth/antiforgery` | Issue/return the antiforgery token used for portal writes. |
| `POST` | `/api/auth/login` | Validate application credentials and create the session. |
| `GET` | `/api/auth/session` | Return the current authenticated user/session. |
| `POST` | `/api/auth/logout` | End the current session. |

## Users and memberships

| Method | Route | Behavior |
|---|---|---|
| `GET` | `/api/users` | List application users. Administrator only. |
| `POST` | `/api/users` | Create an application user. Administrator only. |
| `PATCH` | `/api/users/{id}/status` | Activate or deactivate a user. Administrator only. |
| `GET` | `/api/projects/{projectId}/memberships` | List project memberships. Owner/admin operation. |
| `POST` | `/api/projects/{projectId}/memberships` | Add a Viewer, Contributor or Owner membership, optionally scoped to an environment. |
| `DELETE` | `/api/projects/{projectId}/memberships/{membershipId}` | Remove a membership. |

There are no endpoints for password reset, user deletion, platform-role changes or self-service profile changes.

## Customers, projects and environments

| Group | Implemented routes |
|---|---|
| Customers | `GET /api/customers`, `GET /api/customers/{id}`, `POST /api/customers` |
| Projects | `GET /api/projects`, `GET /api/projects/{id}`, `POST /api/projects` |
| Environments | `GET /api/environments`, `GET /api/environments/{id}`, `POST /api/environments`, `PATCH /api/environments/{id}`, `DELETE /api/environments/{id}` |

Project visibility is membership-filtered for standard users and platform-wide for administrators.

## Database inventory and offline assessment

| Method | Route | Behavior |
|---|---|---|
| `GET` | `/api/databases` | List accessible database inventory, filtered by request parameters and access scope. |
| `GET` | `/api/databases/{id}` | Get one accessible database. |
| `POST` | `/api/databases` | Create a database inventory record. |
| `PATCH` | `/api/databases/{id}` | Update a database inventory record. |
| `GET` | `/api/databases/import-template` | Download the Excel inventory template. |
| `POST` | `/api/databases/import` | Validate and atomically import an Excel inventory workbook. |
| `GET` | `/api/databases/{id}/assessment-script` | Generate a database-specific PowerShell collector. |
| `POST` | `/api/databases/{id}/assessment-results` | Validate and persist offline collector JSON. |

The offline upload path creates a completed assessment job with no agent and records unverified result confidence.

## Portal-managed agents and jobs

| Method | Route | Behavior |
|---|---|---|
| `GET` | `/api/agents` | List accessible agents. |
| `POST` | `/api/agents` | Register an agent and return bootstrap information. |
| `GET` | `/api/agents/{id}/bootstrap` | Retrieve available bootstrap information. |
| `POST` | `/api/agents/{id}/heartbeat` | Portal-side heartbeat operation. |
| `GET` | `/api/agents/{id}/jobs` | List an agent's job history. |
| `POST` | `/api/agents/{id}/jobs` | Dispatch an assessment job. |
| `GET` | `/api/agents/{id}/jobs/{jobId}/results` | List persisted findings for a job. |

## Agent-facing HMAC routes

| Method | Route | Behavior |
|---|---|---|
| `POST` | `/api/agent/{agentId}/heartbeat` | Update agent liveness. |
| `GET` | `/api/agent/{agentId}/jobs/next` | Poll for the next assigned job. |
| `POST` | `/api/agent/{agentId}/results` | Submit structured job findings. |

These routes are anonymous to the portal cookie scheme but are protected by `AgentHmacAuthMiddleware`.

## Questionnaires

| Method | Route | Behavior |
|---|---|---|
| `GET` | `/api/questionnaires/templates` | List questionnaire templates. |
| `GET` | `/api/questionnaires/templates/{id}` | Get an ordered template with sections and questions. |
| `POST` | `/api/questionnaires/templates/seed` | Synchronize bundled JSON templates. |
| `GET` | `/api/questionnaires/responses` | List accessible responses. |
| `POST` | `/api/questionnaires/responses` | Start a response. |
| `GET` | `/api/questionnaires/responses/{id}` | Get a response and answers. |
| `GET` | `/api/questionnaires/responses/{id}/attachments` | List response/question attachments. |
| `PUT` | `/api/questionnaires/responses/{id}/answers` | Save answers. |
| `POST` | `/api/questionnaires/responses/{id}/submit` | Validate required answers and submit. |

## Evidence

| Method | Route | Behavior |
|---|---|---|
| `GET` | `/api/evidence` | List accessible uploaded evidence. |
| `GET` | `/api/evidence/{id}` | Get evidence metadata. |
| `GET` | `/api/evidence/{id}/download` | Download stored evidence content. |
| `POST` | `/api/evidence/upload` | Upload project, database-tagged, response or question evidence. `databaseId` is optional and must belong to `projectId`. |
| `POST` | `/api/evidence/{id}/reparse` | Retry evidence parsing. |
| `DELETE` | `/api/evidence/{id}` | Delete evidence metadata and stored file. |

## Graph and portfolios

| Group | Implemented routes |
|---|---|
| Graph edges | `GET /api/graph/edges`, `POST /api/graph/edges/batch`, `DELETE /api/graph/edges/{edgeId}` |
| Portfolios | `GET /api/portfolios`, `GET /api/portfolios/{id}`, `POST /api/portfolios`, `PATCH /api/portfolios/{id}`, `DELETE /api/portfolios/{id}` |

Graph edges connect database inventory records. Portfolios persist a JSON list of database IDs; they are not migration-wave entities.

## AI configuration and reports

| Method | Route | Behavior |
|---|---|---|
| `GET` | `/api/ai/providers` | List provider registry entries. |
| `POST` | `/api/ai/providers` | Create a provider registry entry. |
| `PATCH` | `/api/ai/providers/{id}` | Update a provider entry. |
| `DELETE` | `/api/ai/providers/{id}` | Delete a provider entry. |
| `GET` | `/api/ai/status` | Return configuration, connection and reporting readiness state. |
| `PUT` | `/api/ai/configuration` | Save active endpoint/deployment configuration and optional credential. |
| `DELETE` | `/api/ai/configuration/credential` | Remove the saved model credential. |
| `POST` | `/api/ai/test` | Perform a real model completion test. |
| `POST` | `/api/ai/enrich/{resultId}` | Enrich one result; used by the worker service identity. |
| `POST` | `/api/ai/generate-report` | Snapshot evidence, call the model and persist a report. Accepts `projectId` and an optional `databaseId`; database scope includes matching database evidence plus project-wide evidence. |
| `GET` | `/api/ai/report-instructions` | Return the effective Markdown report instructions, source, SHA-256 hash and size limit. |
| `PUT` | `/api/ai/report-instructions` | Administrator-only. Atomically update external report instructions. Accepts `content` and the previously read `expectedSha256`; returns `409` if another update won the race. |
| `GET` | `/api/ai/reports` | List accessible persisted reports. |
| `GET` | `/api/ai/reports/{id}` | Get one persisted report. |
| `POST` | `/api/ai/reports/{id}/transition` | Apply a permitted review, approval or export transition. |

Report generation returns `503` when Microsoft Foundry is not configured and successfully tested.

## System endpoints

| Method | Route | Behavior |
|---|---|---|
| `GET` | `/api/system/status` | Return API, database, worker and AI component status. |
| `GET` | `/api/system/config` | List supported system configuration. |
| `PUT` | `/api/system/config` | Save supported system configuration. |
| `DELETE` | `/api/system/config/{key}` | Remove a supported setting. |
| `GET` | `/api/system/agents` | List agents across projects for administration. |

## Error behavior

- `400`: validation or antiforgery failure.
- `401`: missing or invalid session, service token or HMAC authentication.
- `403`: authenticated identity lacks the required role, project or environment access.
- `404`: resource does not exist.
- `409`: state or uniqueness conflict where enforced by a controller.
- `503`: report generation is unavailable because model readiness requirements are not met.
# Project Structure

## Classification

Full-stack monorepo with five deployable/runtime components: React portal, ASP.NET Core API, .NET background worker, .NET assessment agent, and PostgreSQL.

## Feature-Relevant Modules

| Module | Layer | Feature responsibility |
|---|---|---|
| `src/agent/AssessmentToolkit.Agent` | Collection | Connects to Oracle and submits versioned findings. |
| `src/backend/AssessmentToolkit.Api` | API/orchestration | Accepts results, questionnaires and evidence; generates reports; exposes graph and portfolio workflows. |
| `src/backend/AssessmentToolkit.Core` | Domain model | Persisted assessment, evidence, governance, graph and portfolio entities. |
| `src/backend/AssessmentToolkit.Data` | Persistence | EF Core mappings and PostgreSQL schemas. |
| `src/backend/AssessmentToolkit.Worker` | Background processing | Result enrichment, timeouts and health processing. |
| `src/frontend` | Portal | Questionnaire, communication-map, portfolio and report user journeys. |
| `src/tests/AssessmentToolkit.Api.Tests` | Verification | Focused service, authorization, agent and report tests. |

## Feature-Relevant Entry Points

- Agent job execution: `JobPollerService` invokes `OraclePlugin.RunAsync`.
- Agent result submission: `POST /api/agent/{agentId}/results`.
- Questionnaire evidence: `/api/questionnaires/*` and `/api/evidence/*`.
- Report generation: `POST /api/ai/generate-report`.
- Graph management: `/api/graph/edges*`.
- Portfolio management: `/api/portfolios*`.
- Portal routes: `/questionnaire`, `/communication-map`, `/portfolio`, `/reports`.

## Functional Domains

1. Oracle evidence collection
2. Evidence reconciliation and completeness
3. Questionnaire evidence
4. Ordered target assessment
5. Dependency discovery and candidate review
6. Authoritative communication graph
7. Dependency-aware portfolio planning
8. Governed reporting and approval

## Relevant Configuration

- `src/backend/AssessmentToolkit.Api/QuestionnaireTemplates/oracle-v3.json`: current Oracle stakeholder evidence template.
- `report-config/report-instructions.md`: report-generation policy.
- `src/backend/AssessmentToolkit.Api/appsettings.json`: API, storage, AI and local-agent settings.
- `src/agent/AssessmentToolkit.Agent/appsettings.json`: agent polling and logging settings.
- `docker-compose.yml`: local runtime composition.

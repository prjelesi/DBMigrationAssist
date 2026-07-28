# MVP Backlog

_Assessment Toolkit | Epics, user stories, acceptance criteria and release sequencing_

## 1. MVP objective

The MVP should prove the full assessment loop: create a project, configure deployment/storage mode, collect questionnaire inputs, ingest evidence through agents or uploads, create portfolio groups, generate communication maps, classify migration paths, and export reviewed reports.

## 2. Epics

| Epic | Outcome |
| --- | --- |
| E1 Project workspace | Users can create customers, projects and environments. |
| E2 Questionnaire engine | Users can collect baseline business and technical context. |
| E3 Storage abstraction | Files can be stored locally or in a customer-managed connected location. |
| E4 Agent framework | Docker agents can register and submit assessment results. |
| E5 Evidence ingestion | Uploaded reports and raw outputs are parsed and normalised. |
| E6 Inventory and metadata | Databases and related metadata are visible and searchable. |
| E7 Portfolio grouping | Databases can be grouped by environment, application/service and planning logic. |
| E8 Communication maps | Users can visualise and validate dependency flows. |
| E9 Rules and recommendations | System can classify migration paths and unsupported scope. |
| E10 Reports and approvals | Reports can be generated, reviewed, approved and exported. |

## 3. Must-have user stories

| ID | Story | Acceptance criteria |
| --- | --- | --- |
| MVP-001 | As a delivery user, I can create a customer project and select deployment mode. | Project has name, customer, deployment mode, status and audit record. |
| MVP-002 | As a user, I can define environments such as production, UAT, DR and dev. | Databases and agents can be scoped to an environment. |
| MVP-003 | As a project user, I can complete a baseline questionnaire. | Required questions block completion until answered; drafts can be saved. |
| MVP-004 | As an admin, I can configure a storage backend. | Files are stored with metadata, checksum and project boundary. |
| MVP-005 | As an admin, I can register a Docker assessment agent. | Agent has scoped identifier, bootstrap material and heartbeat status. |
| MVP-006 | As an engineer, I can run an assessment job and ingest results. | Job status, result files and findings are visible. |
| MVP-007 | As a user, I can upload customer reports. | Upload creates metadata, parser status and evidence reference. |
| MVP-008 | As a planner, I can group databases into a portfolio. | Portfolio saves members, grouping reason and owner. |
| MVP-009 | As a planner, I can view a communication map. | Graph shows nodes, edges, confidence and evidence source. |
| MVP-010 | As a reviewer, I can approve a generated report. | Draft, review, approval and export states are tracked. |

## 4. Should-have stories

- Private endpoint support for connected AI and storage services.
- Advanced impact analysis and blast-radius scoring.
- Import of CMDB or network-flow exports for communication maps.
- Dependency-aware migration-wave assistant.
- SharePoint publishing approval workflow.

## 5. Could-have stories

- Offline local model packaging where customer policy permits.
- Automated target SKU recommendation.
- Cost-estimate integration.
- Azure DevOps work item creation.
- Migration runbook generation per wave.
- Audience-specific report templates.

## 6. Release sequence

| Increment | Scope |
| --- | --- |
| R0 Foundation | Project, environment, RBAC skeleton, storage abstraction and audit. |
| R1 Evidence loop | Questionnaire, upload, parser shell, inventory and first report template. |
| R2 Agent loop | Agent registration, job execution, result submission and normalisation. |
| R3 Planning loop | Portfolio grouping, communication map, rules matrix and risk register. |
| R4 Reporting loop | AI/rules-based report generation, review, approval and export. |
| R5 Hardening | Air-gapped package, security review, backup/restore and pilot readiness. |

## 7. Definition of done

- Feature is implemented in containerised runtime.
- API and UI paths are covered by tests.
- Audit events are emitted for key state changes.
- Security and RBAC behaviour is validated.
- Documentation exists for user workflow and deployment implications.
- Feature works in at least one MVP deployment mode and has documented limitations for other modes.

## 8. MVP risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Scope expands across too many database engines | Start with common framework and prioritise representative plugins. |
| Graph visualisation becomes complex | Use simple graph plus table fallback in MVP. |
| Air-gapped deployment increases packaging work | Define offline package early and automate image/export scripts. |
| AI integration blocked by customer policy | Ensure rules-based report fallback is first-class. |
| Uploaded report formats vary widely | Use parser registry and confidence scoring. |

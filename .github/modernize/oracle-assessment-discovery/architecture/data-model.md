# Existing Data Model

## Schemas and Relevant Entities

| Schema | Entity | Purpose |
|---|---|---|
| `core` | `Project`, `ProjectEnvironment`, `AppUser`, `ProjectMembership` | Project ownership and authorization scope. |
| `inventory` | `DatabaseInstance` | Assessed database identity and metadata. |
| `assessment` | `Agent`, `AssessmentJob`, `AssessmentResult`, `UploadedReport` | Connected/offline execution, raw findings and uploaded evidence metadata. |
| `questionnaire` | `QuestionnaireTemplate`, `QuestionnaireSection`, `Question`, `QuestionnaireResponse`, `Answer` | Versioned stakeholder evidence and database-scoped answers. |
| `graph` | `GraphEdge`, `Portfolio` | Manually maintained authoritative edges and database-ID groups. |
| `reporting` | `EvidenceBundle`, `GeneratedReport` | Immutable report input snapshot and report lifecycle. |
| `audit` | `AuditEvent` | Successful mutating request audit records. |

## Relevant Relationships

- A project owns databases, agents, questionnaire responses, evidence, graph edges, portfolios, bundles and reports.
- An assessment job belongs to an agent and may target an inventory database.
- An assessment result belongs to one job; `FindingJson` and `RawSummaryJson` contain flexible JSON evidence.
- A questionnaire response belongs to a project, template and optionally one database.
- Uploaded evidence belongs to a project and may reference a database, questionnaire response and question.
- A graph edge links two inventory database IDs in one project.
- A portfolio stores a JSON list of inventory database IDs.
- A generated report references one evidence bundle and optionally one database.

## Existing Transaction Boundaries

- Graph batch save replaces a project's canvas edges in one database transaction.
- Project deletion removes restrict-linked records transactionally before deleting files.
- Report generation persists an evidence bundle and generated report after validating the generated contract.

## Key Preservation Constraints

- Existing graph edges and portfolios contain user-authored information and must not be dropped.
- Original assessment JSON, questionnaire answers, uploads and evidence bundles are historical evidence.
- Database-scoped questionnaire uniqueness must remain enforced.
- Approved generated reports retain evidence-bundle linkage and reviewer/approver history.

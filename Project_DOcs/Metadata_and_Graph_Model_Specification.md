# Metadata & Graph Model Specification

_Assessment Toolkit | Portfolio, dependency and communication-map model_

> **Baseline:** The model represents customers, projects, environments, database estates, portfolios, dependencies, communication flows, risks, recommendations and migration waves.

## 1. Purpose

This specification defines the metadata entities and graph relationships required to build portfolio views, dependency analysis, communication maps, impact analysis and wave-planning inputs.

## 2. Core metadata entities

| Entity | Description | Representative attributes |
| --- | --- | --- |
| Customer | Organisation or tenant being assessed | customer_id, name, industry, region, data_boundary |
| Project | Assessment engagement workspace | project_id, customer_id, name, deployment_mode, status |
| Environment | Logical technical environment | environment_id, project_id, name, type, location, connectivity_zone |
| BusinessService | Business capability or service supported by applications/databases | service_id, name, owner, criticality, rto, rpo |
| ApplicationComponent | Application, service, API, batch job or integration component | application_id, service_id, name, technology, owner |
| DatabaseInstance | Database source or target instance | database_id, engine, version, host, environment_id, criticality |
| Portfolio | Logical grouping for scope and wave planning | portfolio_id, grouping_type, name, owner, readiness_status |
| CommunicationFlow | Directed relationship between two nodes | flow_id, source_node, target_node, protocol, frequency, evidence_source |
| AssessmentResult | Normalised technical findings from agents or uploads | result_id, database_id, plugin, severity, finding_json |
| MigrationWave | Planned migration execution group | wave_id, name, sequence, planned_window, dependency_constraints |

## 3. Graph node types

- Customer, Project, Environment
- BusinessService and ApplicationComponent
- DatabaseInstance, DatabaseSchema and DatabaseObject where detail is required
- ExternalSystem, FileShare, MessageQueue, APIEndpoint and ReportingPlatform
- Portfolio and MigrationWave as planning nodes
- Risk, Recommendation and Decision as governance nodes

## 4. Graph edge types

| Edge type | From -> To | Meaning |
| --- | --- | --- |
| CONTAINS | Project -> Environment; Environment -> DatabaseInstance | Physical or logical containment. |
| SUPPORTS | DatabaseInstance -> ApplicationComponent | Database supports an application component. |
| BELONGS_TO | DatabaseInstance -> Portfolio | Database is grouped into a migration portfolio. |
| COMMUNICATES_WITH | Application/Database/System -> Application/Database/System | Observed or declared communication path. |
| DEPENDS_ON | Node -> Node | Migration or runtime dependency. |
| PART_OF_WAVE | Portfolio/Database -> MigrationWave | Planned migration sequence assignment. |
| HAS_RISK | Database/Portfolio/Wave -> Risk | Risk associated with a scoped entity. |
| EVIDENCED_BY | Finding/Flow/Decision -> UploadedReport/AssessmentResult | Traceability to source evidence. |

## 5. Communication-map attributes

| Attribute | Purpose |
| --- | --- |
| direction | Inbound, outbound or bidirectional path classification. |
| protocol | TCP, JDBC, ODBC, HTTP, file transfer, queue or unknown. |
| port_or_endpoint | Technical endpoint, port or named interface when known. |
| frequency | Real-time, scheduled, batch, ad hoc or unknown. |
| criticality | Business impact if communication path is unavailable. |
| evidence_source | Agent result, report upload, questionnaire, manual entry or imported file. |
| confidence | System-assigned confidence: high, medium, low or unverified. |
| validation_status | Draft, reviewed, confirmed, rejected or superseded. |

## 6. Portfolio grouping rules

- Group by environment when databases belong to the same production, non-production or DR boundary.
- Group by application or business service when dependencies indicate a shared cutover boundary.
- Group by migration path when engines and target platform choices are aligned.
- Group by dependency group when graph analysis identifies tightly coupled nodes.
- Group by migration wave when sequence, business windows and risk are confirmed.

## 7. Graph generation flow

1. Ingest questionnaire, agent outputs and uploaded dependency files.
2. Normalise entities into canonical metadata records.
3. Match duplicate databases, hosts, applications and service names.
4. Create candidate communication flows with evidence references.
5. Apply confidence scoring and mark unvalidated edges.
6. Allow manual review, correction and sign-off.
7. Generate dependency maps, impact views and wave constraints.

## 8. Governance requirements

- Every graph edge must include evidence_source and created_by metadata.
- Manual changes must be audited.
- Rejected edges must be retained for traceability unless retention policy deletes them.
- Approved communication maps must be versioned before export.
- Graph outputs used in reports must reference the graph version used.

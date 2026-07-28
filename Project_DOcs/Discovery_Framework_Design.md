# Discovery Framework Design

_Assessment Toolkit | Agent, report ingestion, questionnaire and evidence correlation design_

## 1. Purpose

This design describes how the toolkit discovers and correlates database estate information from questionnaires, Docker agents, uploaded reports and manually validated inputs. The framework supports both connected and air-gapped deployments.

## 2. Discovery input channels

| Channel | Examples | Use |
| --- | --- | --- |
| Questionnaire | Business drivers, owners, RTO/RPO, compliance, downtime windows | Captures context not discoverable from technical scans. |
| Agent plugins | Oracle, PostgreSQL, SQL Server, MySQL, MongoDB, Cassandra, Sybase | Collects source technical signals using customer-approved execution. See note below on engine scope. |
| Uploaded reports | AWR, Statspack, DMA, MAP, Azure Migrate, DMS, custom CSV/JSON | Allows evidence ingestion without direct database connectivity. |
| Manual validation | Application owner review, dependency confirmation, risk comments | Improves confidence and sign-off quality. |
| Imported files | CMDB exports, network flows, architecture diagrams | Feeds dependency and communication-map creation. |

> **Supported database engine scope:** The authoritative list of database engine types that the toolkit must support is defined in the **Factory service description**. The plugin registry must include a plugin for each source engine covered by the Factory service catalogue. Any engine type added to or removed from the Factory service description requires a corresponding update to the plugin registry and this document.

## 3. Discovery lifecycle

1. Create project and define deployment mode.
2. Define environments and initial scope.
3. Collect baseline questionnaire responses.
4. Register agents or configure report-only ingestion.
5. Run plugins or import approved evidence files.
6. Normalise results into canonical inventory and finding objects.
7. Correlate databases, applications, services and communication flows.
8. Generate candidate portfolios and dependency maps.
9. Flag missing, conflicting or low-confidence inputs.
10. Review, confirm and export assessment deliverables.

## 4. Agent plugin framework

| Component | Responsibility |
| --- | --- |
| Agent runtime | Bootstrap, authentication, local queue, job polling and result submission. |
| Plugin manager | Discovers installed plugins and validates allowed plugin scope. |
| Plugin executor | Runs database-specific checks with configured credentials and constraints. |
| Result normaliser | Transforms plugin output into a canonical JSON result contract. |
| Evidence packager | Packages result files, checksums, logs and metadata for backend ingestion. |

## 5. Plugin result contract

- project_id, environment_id, agent_id, plugin_id and execution_id
- source engine, version, host and database identifiers
- assessment timestamp and plugin version
- findings grouped by category and severity
- dependency and communication observations where technically feasible
- raw evidence file references and checksums
- warnings, skipped checks and permission limitations

## 6. Report ingestion framework

1. Upload report to configured storage.
2. Create UploadedReport metadata with checksum and provenance.
3. Select parser based on file type, declared source and optional customer tags.
4. Extract structured values and persist raw parse output.
5. Normalise extracted values into inventory, findings or graph candidates.
6. Mark parse confidence and route low-confidence outputs for review.

## 7. Evidence confidence model

| Confidence | Typical source | Handling |
| --- | --- | --- |
| High | Direct agent result or validated customer source | Can be used for recommendations and reports. |
| Medium | Uploaded reports with successful parser and partial validation | Usable with review notice. |
| Low | Manual free-text or weakly matched imported data | Requires confirmation before planning decisions. |
| Unverified | Inferred candidate dependency or conflicting source | Visible as draft only. |

## 8. Air-gapped behaviour

- All parsers, plugins and templates must be included in the offline package.
- Agent-to-backend communication must work without internet access.
- AI narrative generation must be disabled unless an approved local/private endpoint exists.
- Rules-based reports must be available using local templates and migration-path rules.
- Offline updates must be delivered through signed, versioned bundles.

## 9. MVP discovery scope

- Questionnaire engine with required/optional questions and completion states.
- Docker agent registration and job execution.
- Plugin coverage for the relational engine types listed as priority in the Factory service description; at minimum one fully implemented relational plugin and one upload-based ingestion path for MVP.
- Canonical result contract and normalisation pipeline.
- Portfolio grouping and communication-map candidate generation.
- Missing information and evidence-quality review view.

# PostgreSQL Data Model

_Assessment Toolkit | Relational schema, graph tables and operational metadata_

## 1. Purpose

This document defines an initial PostgreSQL-oriented data model for the Assessment Toolkit. It is designed to support project metadata, database inventories, graph relationships, file evidence, assessment results, reporting, approvals and audit.

## 2. Schema layout

| Schema | Purpose |
| --- | --- |
| core | Customers, projects, environments, users and RBAC. |
| inventory | Applications, services, database instances and infrastructure metadata. |
| assessment | Agents, jobs, plugins, results and uploaded reports. |
| graph | Nodes, edges, communication flows, portfolios and impact analysis. |
| planning | Recommendations, risks, migration waves and decisions. |
| reporting | Evidence bundles, generated reports, reviews and exports. |
| audit | Immutable audit events and operational logs. |

## 3. Key tables

| Table | Primary key | Purpose |
| --- | --- | --- |
| core.customer | customer_id | Customer or organisation boundary. |
| core.project | project_id | Assessment engagement workspace. |
| core.environment | environment_id | Production, UAT, DR, dev or custom environment. |
| inventory.business_service | service_id | Business service context. |
| inventory.application_component | application_id | Application, API, batch job or integration component. |
| inventory.database_instance | database_id | Database engine instance or database service. |
| assessment.agent | agent_id | Registered Docker assessment agent. |
| assessment.assessment_job | job_id | Work item assigned to agent or upload parser. |
| assessment.assessment_result | result_id | Normalised result or finding. |
| assessment.uploaded_report | report_id | Uploaded report metadata and file pointer. |
| graph.node | node_id | Canonical graph node record. |
| graph.edge | edge_id | Canonical graph relationship. |
| graph.communication_flow | flow_id | Typed communication path between nodes. |
| graph.portfolio | portfolio_id | Database grouping for planning. |
| planning.migration_wave | wave_id | Migration execution group. |
| planning.risk | risk_id | Risk register item. |
| reporting.generated_report | generated_report_id | Draft or approved generated report. |
| audit.audit_event | audit_event_id | Immutable user/system action. |

## 4. Recommended column patterns

| Pattern | Columns |
| --- | --- |
| Identity | uuid primary key default gen_random_uuid() |
| Tenant/project scoping | customer_id, project_id, environment_id where applicable |
| Lifecycle | status, created_at, created_by, updated_at, updated_by, deleted_at |
| Evidence | source_type, source_id, evidence_confidence, evidence_hash |
| JSON extension | metadata_json jsonb, finding_json jsonb, raw_summary_json jsonb |
| Governance | review_status, approved_by, approved_at, version_number |

## 5. Example DDL fragment

```sql
CREATE TABLE inventory.database_instance (
    database_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id uuid NOT NULL REFERENCES core.project(project_id),
    environment_id uuid REFERENCES core.environment(environment_id),
    name text NOT NULL,
    engine text NOT NULL,
    version text,
    host_name text,
    port integer,
    criticality text,
    owner_name text,
    metadata_json jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
```

## 6. Indexing guidance

- Add composite indexes on project_id and environment_id for all scoped tables.
- Use GIN indexes for JSONB fields that support filtering and report generation.
- Index graph.edge(source_node_id), graph.edge(target_node_id) and graph.edge(edge_type).
- Use unique constraints to prevent duplicate active portfolio membership for the same database and portfolio.
- Partition or archive audit events if volumes become large.

## 7. Data retention and classification

| Data class | Examples | Retention handling |
| --- | --- | --- |
| Raw evidence | Uploaded reports, raw agent output | Retain according to project policy; isolate from approved outputs. |
| Normalised findings | AssessmentResult rows, graph edges | Retain while project is active and for agreed audit period. |
| Generated drafts | Draft AI or rules-based reports | Purge or archive after approval workflow. |
| Approved deliverables | Final reports and exports | Version and retain according to customer/project policy. |
| Audit | Logins, uploads, approvals, exports | Immutable retention with restricted access. |

## 8. Open design choices

- Whether to use pure relational graph tables or add a graph extension later.
- Whether to store large JSON result payloads in PostgreSQL or file storage with a metadata pointer.
- Whether application inventory remains excluded from MVP or represented only through optional manual entries.
- How strict duplicate matching should be for database names, hosts and service relationships.

# Banana Inc Assessment and Follow-up Plan

## Phase 1: Confirm scope and ownership

- Validate the seven-database inventory and identify all non-production and DR copies.
- Assign business, application, database, network, security and vendor owners.
- Approve target preference order and clarify that it does not guarantee PostgreSQL suitability.
- Confirm datacenter-exit deadline, budget, licensing baseline and decision dates.

## Phase 2: Collect evidence

- Run the toolkit Oracle collector with a reviewed read-only account against each database.
- Collect AWR or Statspack from representative normal, peak and close periods.
- Export object/code summaries and identify wrapped code requiring owner review.
- Complete the project-wide baseline questionnaire.
- Complete the Oracle questionnaire separately for every database.
- Validate the application/dependency and Oracle feature CSV registers.
- Gather vendor support matrices, architecture diagrams, runbooks and recovery test results.

## Phase 3: Target assessments

For each database, perform PostgreSQL compatibility and effort analysis first. Where a hard gate fails, retain the evidence and assess Azure SQL. Assess Oracle on Azure VMs only after both managed branches fail or when a time-bounded interim rehost is explicitly justified.

Proofs of concept must use representative schema complexity, data volume, query mix, integrations, security controls and recovery procedures. A schema-only conversion is not sufficient.

## Workshops

| Workshop | Required attendees | Outputs |
| --- | --- | --- |
| Business and portfolio | Sponsor, product owners, finance, architecture | Scope, priority, deadline, critical periods and decision criteria |
| Application deep dives | App owners, developers, vendor representatives | Code dependencies, certification, tests and remediation estimates |
| Oracle technical discovery | DBAs, performance and storage teams | Feature inventory, AWR interpretation, sizing and recovery baseline |
| Integration and network | Integration, network, cloud platform, security | Interface register, routing, DNS, firewall and migration bandwidth |
| Security and privacy | Security, privacy, audit, platform owners | Data classification, control gaps, logging and migration approval path |
| Target decision | Architecture board and workload owners | Target recommendation, fallback, risks, wave and approval record |

## Follow-up questions

### Application and vendor

- Is PostgreSQL contractually supported for each packaged application and version?
- If only SQL Server is supported, is Azure SQL Managed Instance certified?
- Which SQL and business logic lives outside application source control?
- Are automated functional, reconciliation, performance and failover tests available?

### Database and operations

- Which Oracle options are licensed and actively used rather than merely installed?
- What are measured CPU, memory, IOPS, throughput, growth and daily change rates?
- Which databases require RAC semantics, and which only require service availability?
- When were restore, Data Guard failover and application recovery last tested?

### Migration

- What downtime can each owner approve, and what is the rollback deadline?
- Can CDC run through the required security zones and for how long?
- Which financial and operational totals provide authoritative reconciliation?
- Can integration redesign precede database cutover?

### Security

- Which datasets require masking in non-production?
- Are customer-managed keys mandatory or optional by classification?
- What log retention and privileged-session recording are required?
- Who approves temporary migration access and verifies its removal?

## Deliverables

- Validated inventory and dependency map.
- Per-database compatibility and target decision record.
- Application remediation backlog and vendor support evidence.
- Target network/security architecture and operations model.
- Sizing and five-year cost comparison for viable alternatives.
- Migration waves, pilot plan, cutover/rollback strategy and RAID register.
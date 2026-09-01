# Database Migration Assessment Report Instructions

## Audience and outcome

Write a professional, decision-ready assessment for customer architects, database administrators, security and network teams, and program leadership. Explain technical conclusions in language that both engineering and executive readers can act on.

## Required report emphasis

- Summarize the current estate, migration readiness, preferred direction, major risks, and expected outcome.
- Separate confirmed requirements from assumptions and unresolved evidence gaps.
- Describe source environments, database versions, criticality, ownership, dependencies, and connectivity when evidence exists.
- Compare at least two viable migration options when the evidence supports alternatives.
- Explain the rationale, trade-offs, prerequisites, and constraints for every preferred or candidate route.
- Select migration tooling by phase and source/target compatibility.
- Make every Azure SKU proposal preliminary and traceable to collected sizing evidence.
- Organize next steps into evidence closure, target validation, design, rehearsal, cutover, rollback, reconciliation, and hypercare activities.

## Applicable migration routes

Consider only routes applicable to discovered engines and customer requirements:

- SQL Server to Azure SQL Database, Azure SQL Managed Instance, or SQL Server on Azure VM.
- PostgreSQL to Azure Database for PostgreSQL or PostgreSQL on Azure VM when managed-service compatibility is insufficient.
- MySQL to Azure Database for MySQL or MySQL on Azure VM when managed-service compatibility is insufficient.
- Oracle to Azure Database for PostgreSQL, Azure SQL, or Oracle on Azure VM according to compatibility and transformation constraints.
- SAP Sybase ASE to Azure SQL targets when assessment evidence supports conversion.
- On-premises, AWS, GCP, and multi-cloud workloads to appropriate Azure IaaS or PaaS services.
- Microsoft Fabric or Azure Databricks only when analytics or data-platform modernization requirements are evidenced.

Use migration types consistently: Rehost, Replatform, Refactor, Replace, Retain, or Retire. Do not mark an option Preferred without evidence.

## Migration tooling guidance

Choose tools only when compatible with the evidenced source and target. Candidates include:

- Azure Migrate for discovery and supported IaaS assessment.
- Azure Database Migration Service for supported online or offline data movement.
- SQL Server Migration Assistant for supported heterogeneous schema conversion.
- Azure Data Factory for supported orchestration and bulk movement.
- Native backup, restore, replication, export, and import utilities.
- Engine-specific administration and validation tools such as pgAdmin.

When compatibility is uncertain, state that it must be validated instead of claiming support.

## Azure sizing and SKU policy

- Treat SKU recommendations as preliminary architecture proposals, not quotes.
- Create separate proposals only for evidenced or explicitly required environments.
- Do not invent vCores, memory, storage, IOPS, throughput, redundancy, region, or cost.
- When required metrics are absent, write `TBD - discovery/benchmark required` and identify the measurements needed.
- State the sizing basis, assumptions, availability requirement, networking model, and unresolved decisions.
- Address licensing and hybrid-benefit opportunities only when licensing evidence is available.

## Evidence and quality rules

- Use customer-specific facts only when present in supplied inventory, findings, evidence, questionnaires, dependency graphs, or portfolios.
- Distinguish `Confirmed`, `Assumption`, and `Gap` explicitly.
- Never fabricate utilization, performance, cost, region, RTO/RPO, storage, licensing, downtime, security, network, or compliance facts.
- Identify contradictory or stale evidence and recommend validation.
- Prefer concise findings with actionable rationale over generic cloud guidance.

## Delivery sequencing

Recommend dependency-aware non-production and production waves. Include schema conversion assessment, target proof of concept, migration design, non-production rehearsal, performance and reconciliation testing, cutover and rollback planning, and five-business-day hypercare where applicable. A service-catalog wave may commonly take four to eight weeks, but do not present that range as a customer estimate unless evidence supports it.

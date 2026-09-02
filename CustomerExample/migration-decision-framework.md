# Banana Inc Migration Decision Framework

## Decision policy

Evaluate each workload independently in this strict order:

1. Can the application and database safely run on PostgreSQL Flexible Server?
2. If not, can they safely run on Azure SQL Database or SQL Managed Instance?
3. If neither managed target is feasible within approved risk, use Oracle on Azure VMs as a documented fallback or interim state.

A failed proof of concept is evidence, but preference alone is not. Record the failed gate and remediation estimate before moving to the next target.

## Gates

| Gate | PostgreSQL evidence | SQL evidence | IaaS fallback evidence |
| --- | --- | --- | --- |
| Vendor support | Written PostgreSQL certification or customer-owned support decision | Written SQL Server/Azure SQL certification | Supported Oracle version/OS/topology |
| Feature compatibility | Oracle objects mapped, extensions approved, code conversion tested | Oracle objects mapped, T-SQL conversion tested | Oracle features and licenses supported on chosen VM design |
| Application change | Drivers, SQL, ORM and transaction behavior pass tests | Drivers, SQL, ORM and transaction behavior pass tests | Connection, host and operational changes pass tests |
| Performance | Representative load meets latency/throughput and scaling targets | Representative load meets latency/throughput and scaling targets | VM/storage design meets AWR-derived demand |
| Availability | Zone/HA design meets RTO/RPO | Service-tier/HA design meets RTO/RPO | Oracle HA/DR architecture meets RTO/RPO |
| Migration | Initial load, CDC, validation and cutover fit the window | Initial load, CDC, validation and cutover fit the window | Backup/restore or replication approach fits the window |
| Security | Identity, private network, audit and encryption controls approved | Identity, private network, audit and encryption controls approved | OS, Oracle, network and privileged controls approved |
| Economics | Five-year cost including conversion and operations approved | Five-year cost including conversion and operations approved | Licensing, VM, storage and DBA cost accepted |

## Initial hypotheses by workload

| Workload | Preferred branch | Why it starts there | Condition that moves it to the next branch |
| --- | --- | --- | --- |
| PeelPay Commerce | PostgreSQL | Modern Java stack and mostly portable persistence | PL/SQL conversion or peak transaction tests fail within acceptable remediation effort |
| Customer services | PostgreSQL | Service-owned data and manageable size | VPD/AQ replacement or privacy controls cannot be validated |
| CrateFlow WMS | PostgreSQL assessment, likely SQL second | Managed service preferred, but vendor support is uncertain | Vendor declines PostgreSQL or warehouse regression/support gate fails |
| RipenTrack Integration | PostgreSQL after decoupling | AQ and database links should become platform integration services | Redesign cannot fit timeline; assess SQL, then temporary Oracle VM |
| LedgerLeaf Finance | Modernization assessment, likely Oracle VM interim | Forms/Reports and extensive PL/SQL couple app and database | PostgreSQL/SQL business case does not support full application change in the exit window |
| PeopleStem HR | PostgreSQL assessment, SQL second | Packaged vendor controls supported platform | Vendor certifies SQL but not PostgreSQL; Oracle VM only if neither managed option is supported |
| BananaBoard Analytics | PostgreSQL plus analytical platform review | Read-heavy serving is portable and history can be separated | Query/performance or tooling constraints favor SQL; avoid putting all history on IaaS by default |

## Suggested migration waves

| Wave | Scope | Exit criteria |
| --- | --- | --- |
| 0 - Discovery | All databases and applications | Inventory, AWR, feature scan, dependencies, vendor matrices and RTO/RPO approved |
| 1 - PostgreSQL pilot | Reporting subset or Customer non-production | Converted schema, representative data, security controls and regression/load tests pass |
| 2 - Lower-coupling production | Customer and Commerce | CDC/cutover rehearsal, reconciliation and rollback approved |
| 3 - Integration and warehouse | Integration redesign and CrateFlow target | Interfaces decoupled, vendor support proven, peak dispatch tests pass |
| 4 - Packaged/core systems | HR and Finance | Product strategy approved; managed conversion or IaaS fallback implemented with DR |

## Decision record template

For each database, the final report should state:

- Recommended target and whether it is strategic or interim.
- Alternatives assessed and the evidence-backed reason each was rejected.
- Required application, schema, integration and operating-model changes.
- Migration method, downtime estimate, validation and rollback approach.
- Target sizing basis and assumptions.
- Security, compliance, availability and recovery controls.
- Cost estimate, license impact, delivery effort and major risks.
- Decision owner, approvers and review date.
# Banana Inc Customer Profile

## Organization

Banana Inc is a fictional food distribution company serving retailers and restaurants across Northern Europe. It runs ordering, warehouse, finance, people and analytics services from a primary datacenter in Stockholm with recovery capacity in Gavle.

| Attribute | Fictional value |
| --- | --- |
| Industry | Food distribution and logistics |
| Headquarters | Stockholm, Sweden |
| Employees | 4,800 |
| Operating model | 24x7 ordering and warehouse operations |
| Azure region preference | Sweden Central, paired recovery design to be confirmed |
| Regulatory context | GDPR, payment controls, financial audit and internal security policy |

## Business drivers

- Exit aging datacenter hardware within 24 months.
- Reduce Oracle licensing and specialist operating costs where modernization is feasible.
- Prefer managed Azure database services over virtual machines.
- Preserve peak-season availability and order-processing performance.
- Improve automated recovery, observability and security governance.
- Avoid a single portfolio-wide target that ignores application constraints.

## Target preference

Each database must be evaluated in the following order:

1. **PostgreSQL Flexible Server**: preferred for open-platform economics, managed operations and future application modernization.
2. **Azure SQL**: second choice where the application or vendor supports SQL Server but not PostgreSQL, or where Microsoft data-platform integration materially lowers change risk.
3. **Oracle on Azure VMs**: fallback for workloads blocked by packaged-software certification, extensive Oracle coupling, or requirements that cannot be met safely by either managed target in the project window.

## Scope

The first assessment covers seven production Oracle databases and the six application groups that depend on them. Development, test and recovery copies must be inventoried during discovery but are not represented as separate rows in the initial import workbook.

## Initial success measures

- Every database has an evidence-backed target recommendation and fallback.
- Vendor support statements are recorded for packaged applications.
- Unsupported Oracle features and required application changes are quantified.
- RTO, RPO, downtime and peak-throughput requirements are approved by owners.
- Security signs off the data flows and target controls before a production pilot.
- At least one PostgreSQL candidate completes a representative proof of concept.

## Assumptions requiring confirmation

- ExpressRoute capacity is available for assessment and migration traffic.
- A 19c source upgrade is possible for the remaining 12.2 workload if required by tooling.
- Application teams can provide source code, integration contracts and regression tests.
- Banana Inc can provision read-only Oracle assessment accounts and representative AWR reports.
- No target decision has yet been approved by architecture, security or application owners.
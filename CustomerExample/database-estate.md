# Banana Inc Oracle Database Estate

The values below are fictional discovery assumptions. They must not be treated as collected facts.

| Database | Version/topology | Size | Main consumers | Key Oracle features to verify | First hypothesis | Fallback |
| --- | --- | ---: | --- | --- | --- | --- |
| `ora-commerce-prod` | 19.20, single instance with Data Guard | 2.4 TB | PeelPay Commerce | PL/SQL packages, partitioning, sequences, triggers | PostgreSQL Flexible Server | Azure SQL Managed Instance, then Oracle VM |
| `ora-customer-prod` | 19.20, single instance with Data Guard | 1.1 TB | PeelPay Commerce, customer service | VPD, advanced queues, materialized views | PostgreSQL Flexible Server | Azure SQL Managed Instance, then Oracle VM |
| `ora-warehouse-prod` | 12.2.0.1, two-node RAC | 3.8 TB | CrateFlow WMS | RAC, AQ, partitioning, database links, hints | PostgreSQL if vendor certifies | Azure SQL Managed Instance, then Oracle VM |
| `ora-integration-prod` | 19.18, single instance | 650 GB | RipenTrack, CrateFlow | AQ, scheduler, database links, external tables | PostgreSQL after integration redesign | Azure SQL Managed Instance, then Oracle VM |
| `ora-finance-prod` | 19.20, two-node RAC with Data Guard | 5.2 TB | LedgerLeaf Finance | Forms/Reports coupling, extensive PL/SQL, TDE, scheduler | Assess modernization/replacement | Oracle on Azure VM likely interim fallback |
| `ora-hr-prod` | 19.19, single instance with Data Guard | 900 GB | PeopleStem HR | Vendor schema, TDE, fine-grained auditing, scheduler | PostgreSQL if vendor certifies | Azure SQL Managed Instance, then Oracle VM |
| `ora-reporting-prod` | 19.18, single instance | 7.5 TB | BananaBoard Analytics | Materialized views, bitmap indexes, database links, compression | PostgreSQL serving tier plus analytical platform review | Azure SQL Managed Instance, then Oracle VM |

## Data and workload assumptions

| Database | Peak pattern | Initial RTO | Initial RPO | Data classification |
| --- | --- | ---: | ---: | --- |
| `ora-commerce-prod` | Daily lunch/evening peaks and seasonal campaigns | 30 min | 5 min | Confidential, payment references |
| `ora-customer-prod` | Follows commerce traffic | 30 min | 5 min | Restricted personal data |
| `ora-warehouse-prod` | Continuous with early-morning dispatch peak | 15 min | 5 min | Confidential operations |
| `ora-integration-prod` | Partner batch windows and continuous queues | 60 min | 15 min | Mixed confidential business data |
| `ora-finance-prod` | Month-end and year-end close | 60 min | 15 min | Restricted financial data |
| `ora-hr-prod` | Payroll and monthly close | 4 hr | 1 hr | Restricted employee data |
| `ora-reporting-prod` | Nightly load and business-hours queries | 8 hr | 4 hr | Aggregated with selected personal data |

These recovery values require owner approval and business-impact evidence.

## Required database evidence

- Version, edition, options, patches, character set, CDB/PDB and RAC topology.
- AWR or Statspack for normal and peak periods, including CPU, memory, I/O and waits.
- Schema/object counts, invalid objects and code volume by object type.
- PL/SQL complexity, dynamic SQL, autonomous transactions and wrapped code.
- Partitioning, compression, materialized views, bitmap indexes and optimizer hints.
- AQ, scheduler, database links, external tables, directories and file dependencies.
- TDE, VPD, fine-grained auditing, database vault and privileged account usage.
- Database size, daily change rate, largest tables and growth history.
- Backup, restore, Data Guard, RAC, RTO, RPO and tested recovery procedures.
- Licensing and vendor certification constraints.

The detailed assumption register is in `evidence/oracle-feature-register.csv`.
# Banana Inc Oracle Migration Example

This folder is a fictional customer evidence pack for demonstrating the Database Migration Assessment Toolkit. Names, systems, volumes, constraints and contacts are invented. The pack contains no real customer or personal data.

## Scenario

Banana Inc is a global food distribution company operating seven Oracle production databases from two on-premises datacenters. The company wants to exit its current hardware platform and migrate to Azure.

The target preference is evaluated in this order for every workload:

1. Azure Database for PostgreSQL Flexible Server.
2. Azure SQL Database or Azure SQL Managed Instance.
3. Oracle Database on Azure virtual machines as the compatibility fallback.

Preference is not a decision. Application support, Oracle feature usage, performance, availability, recovery, security and migration-window evidence must support the selected target.

## Folder contents

| Path | Purpose |
| --- | --- |
| `DEMO_GUIDE.md` | Presenter runbook for loading and demonstrating this customer example. |
| `customer-profile.md` | Business drivers, scope, assumptions and success measures. |
| `application-landscape.md` | Applications, owners, technology stacks and database dependencies. |
| `peelpay-commerce-application.md` | Detailed fictional PeelPay Commerce architecture, workflows, Oracle dependencies and migration criteria. |
| `database-estate.md` | Oracle estate details and workload-specific assessment hypotheses. |
| `network-topology.md` | Current and proposed network diagrams, flows and connectivity requirements. |
| `security-and-compliance.md` | Data classification, identity, encryption, logging and control requirements. |
| `migration-decision-framework.md` | PostgreSQL-first decision gates, fallback rules, waves and required evidence. |
| `assessment-plan.md` | Follow-up workshops, collection activities and deliverables. |
| `database/README.md` | Runnable Oracle commerce schema, PL/SQL logic, fictional data and setup instructions. |
| `evidence/database-inventory.xlsx` | Import-ready toolkit database inventory. |
| `evidence/database-inventory-source.csv` | Human-readable source for the workbook. |
| `evidence/application-database-dependencies.csv` | Application-to-database and interface register. |
| `evidence/oracle-feature-register.csv` | Initial Oracle feature assumptions to verify through discovery. |

## Load into the toolkit

1. Create customer `Banana Inc`, industry `Food Distribution`, region `Northern Europe`.
2. Create project `Banana Inc Oracle Exit`, mode `Connected`.
3. Create these environments before importing the workbook:

   | Name | Type | Location | Connectivity zone |
   | --- | --- | --- | --- |
   | Banana Primary Datacenter | PROD | Stockholm | On-Premises Production |
   | Banana Recovery Datacenter | DR | Gavle | On-Premises Recovery |
   | Azure Migration Landing Zone | UAT | Sweden Central | Azure Private Network |

4. Open **DB Inventory**, select the project, choose **Import Spreadsheet**, and upload `evidence/database-inventory.xlsx`.
5. Upload the Markdown and CSV files as supporting evidence where useful.
6. Complete the Database Migration Baseline once for the project and the Oracle supplemental questionnaire for each database.
7. Run connected or offline Oracle collection and replace every assumption in this pack with collected evidence.

For a runnable source workload, install the [Banana Commerce Oracle sample](database/README.md) into the repository's disposable Oracle lab or another Oracle 19c/21c test schema.

The workbook imports inventory only. Application relationships, target hypotheses and security requirements remain assessment evidence and should be reflected in the communication map, questionnaires and generated report.

For a timed walkthrough, expected import checks, suggested dependency-map entries and assessment waves, follow the [Banana Inc demo guide](DEMO_GUIDE.md).
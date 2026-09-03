
All application names and details are fictional.

## Application summary

| Application | Business purpose | Technology | Databases | Availability | Initial target hypothesis |
| --- | --- | --- | --- | --- | --- |
| PeelPay Commerce | Online ordering, pricing and payment orchestration | Java 17, Spring Boot, Kubernetes | `ora-commerce-prod`, `ora-customer-prod` | 24x7; 99.95% target | PostgreSQL preferred; isolate payment tokens and convert PL/SQL pricing logic. |
| CrateFlow WMS | Warehouse execution, picking and stock movement | Vendor .NET 8 services and Windows clients | `ora-warehouse-prod`, `ora-integration-prod` | 24x7; 15-minute RTO assumption | Vendor supports SQL Server but PostgreSQL certification is unknown; test PostgreSQL first, then SQL Managed Instance. |
| LedgerLeaf Finance | General ledger, invoicing and statutory close | Oracle Forms/Reports and PL/SQL batch | `ora-finance-prod` | Critical during month end | Strong Oracle coupling makes Azure VM the likely fallback unless application replacement is approved. |
| PeopleStem HR | Payroll, workforce and time management | YellowHR packaged Java application | `ora-hr-prod` | Business critical; payroll windows | Obtain vendor matrix. PostgreSQL first; SQL Managed Instance if that is the supported non-Oracle platform. |
| RipenTrack Integration | Partner EDI, queues and scheduled data exchange | Java integration services, Oracle AQ, SFTP | `ora-integration-prod` and database links to four databases | High | PostgreSQL plus Service Bus/Event Grid preferred after decoupling AQ and database links. |
| BananaBoard Analytics | Operational dashboards and demand forecasting | Power BI, Python, scheduled ETL | `ora-reporting-prod`, read-only links to operational databases | High; four-hour freshness target | PostgreSQL preferred for serving; move historical analytical data to Fabric or ADLS where justified. |

## Dependency narrative

### PeelPay Commerce

PeelPay owns customer baskets, orders, price calculations and payment references. Most persistence uses JDBC and an ORM, but promotional pricing and order-number allocation use PL/SQL packages, sequences and triggers. It synchronously calls Customer DB and publishes order events to RipenTrack. PostgreSQL is credible if package logic is moved into services or converted and transaction semantics pass regression testing. The [PeelPay Commerce application dossier](peelpay-commerce-application.md) documents the fictional architecture, workflows, service levels, interfaces and migration acceptance criteria.

### CrateFlow WMS

CrateFlow controls warehouse picking and cannot tolerate prolonged database unavailability. The vendor currently documents Oracle and SQL Server support; PostgreSQL support is an open commercial question. The application also exchanges stock updates through Oracle AQ and a database link. The assessment must separate technical portability from vendor support. If PostgreSQL is not supportable, SQL Managed Instance is preferred over Oracle IaaS.

### LedgerLeaf Finance

LedgerLeaf contains extensive Forms, Reports, PL/SQL packages, scheduler jobs and audit triggers. Month-end close has strict performance and reconciliation requirements. Database conversion alone would not remove the Oracle dependency because the application tier is Oracle-specific. The project should compare full application modernization or replacement with a time-bounded rehost to Oracle on Azure VMs.

### PeopleStem HR

PeopleStem stores employee and payroll data. It is a packaged product, so the vendor support matrix and upgrade path are hard gates. PostgreSQL remains the first assessment branch, but SQL Managed Instance is the second branch if it is the only certified managed alternative. Security testing must cover privileged support access, masking and payroll audit retention.

### RipenTrack Integration

RipenTrack uses Oracle AQ, scheduler jobs, SFTP and database links as an integration hub. A direct database conversion would preserve undesirable coupling. The preferred design replaces AQ with Azure Service Bus, file transfer with controlled storage endpoints, and database links with APIs or event-driven contracts before moving persistence to PostgreSQL.

### BananaBoard Analytics

BananaBoard reads a reporting database populated by nightly ETL and selected database links. Its four-hour freshness requirement does not demand synchronous operational links. A PostgreSQL serving store is feasible, while large history and forecasting datasets may fit Fabric or ADLS better than either PostgreSQL or SQL.

## Interface inventory

The detailed register is in `evidence/application-database-dependencies.csv`. During discovery, confirm protocol, direction, frequency, data classification, retry behavior, owner and cutover sequencing for every interface. Represent database-to-database dependencies in the toolkit communication map and retain application dependencies in this evidence document.
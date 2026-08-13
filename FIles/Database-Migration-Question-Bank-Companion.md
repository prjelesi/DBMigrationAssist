# Database Migration Question Bank

Companion volume — SQL Server, MySQL, MongoDB and PostgreSQL engagements

Cloud Accelerate Factory EMEA · Predrag Jelesijevic

Compiled 14 August 2026

*Companion to the Oracle-to-PostgreSQL kickoff question pack.*

## How to use this pack

This companion volume covers the database migration engagements that fall outside the Oracle-to-PostgreSQL set: eight engagements across four target platforms — Azure SQL and SQL Managed Instance, Azure Database for MySQL, Azure Database for PostgreSQL Flexible Server, and Azure Cosmos DB for MongoDB.

Section 2 is the reusable part. It merges every question into twelve themes, with the engagement that raised each one shown in square brackets so you can trace it back to its context. Run it as a discovery checklist for a new kickoff, regardless of engine.

Section 3 is the traceable record: each engagement in full, with its sources, the questions as they were actually asked, and a short note on what makes it worth revisiting.

Section 4 records coverage and gaps — what was retrievable and what was not.

*Every question in this document is grounded in a meeting transcript, meeting minutes, or an email thread retrieved from your mailbox and calendar. Nothing has been invented. Where a source could not be retrieved, that is stated explicitly rather than filled in.*

## Master question bank

Questions are grouped by theme and de-duplicated across engagements. Bracketed tags identify where the question was raised.

### 1. Scope, workloads and inventory

- How many databases, schemas and servers are in scope for this wave? [BASF: ~4 schemas; VINCI: 78 databases]
- Is the migration scope only the database component, or does it include the application layer? [VINCI — only the SQL/DB portion of the ArcGIS service]
- Is the source database shared by multiple customers, or is it one customer per database? [Schneider]
- Can the migration be split into bite-size subsets, for example per customer, rather than moving the whole database at once? [Schneider]
- Is data distributed across many tables, or concentrated in a few very large ones? [Schneider — one log-history table held ~90% of the data]
- Should legacy or aged data be archived rather than migrated? [ASDA — ~6 GB of signatures older than 14 months archived instead of migrated]
- Which databases are concrete candidates for cloud migration, and is there a finalised candidate list with an ETA? [ABB]
- What criteria decide each database’s path — standard upgrade, full modernisation, or move to PaaS — and what are the pros and cons of each? [ABB]
- How many documents and collections are being migrated? [Mavriq]

### 2. Source environment and versions

- Is the source on-premises, on another cloud, or virtualised? [VINCI; Schneider; BASF — AWS RDS; Holistic AI — Neon]
- What version and edition runs at source, and is the same version used across all prod and non-prod environments? [BASF — MySQL 8.4; Mavriq — MongoDB 4.2; Schneider — Oracle 11G; ABB — SQL Server 2016]
- Does the “option group membership” value represent the actual database version, and is that version supported for migration? [BASF]
- Are there only dev and prod environments, or is there a test, stage or QA tier in between? [BASF — dev, quali and prod]
- How large is the source database? [Schneider ~4 TB; ASDA ~250–350 GB; BASF ~250 GB; Holistic AI ~20–50 GB; Mavriq ~5 GB]
- What is the rate of change or delta volume, so the replication pipe can be sized? [VINCI]
- Is there only one production server, and is replication or HA — secondary zone, read replica — enabled? [BASF]
- Is High Availability (Always On / availability groups) configured, and is TDE or encryption enabled? [VINCI]
- Are there linked servers, reporting services, or third-party links that could block migration? [VINCI]
- Is Azure Arc enabled, so estate details such as versions, collations and patch levels can be shared directly? [VINCI]

### 3. Assessment and discovery scripts

- Can the customer run the Factory-provided assessment script on the source server and return the output? [BASF; ASDA; Schneider]
- Will the assessment script impact the source system or capture any critical or production data? Confirmed metadata-only. [BASF]
- Is it acceptable to share the assessment script for the customer to execute, and is the GitHub repository public? [Schneider]
- Will the DBAs follow the README steps 1–5 and return the generated output? [ASDA]
- Has the assessment input workbook been filled in and shared along with the output files? [BASF]
- What does the assessment look for — database count, sizes, schema structure, primary keys, large objects, target SKU sizing, and an offline-versus-online recommendation? [Holistic AI]
- Does the assessment show the databases as ready for the target platform, and are the blockers at instance level or network level? [VINCI]
- What are the next steps once assessment files are shared and reviewed — current SKU, suggested SKU, mitigation and migration plan, walkthrough? [BASF]
- If the customer does not fully know their application and database dependencies, how do we start the migration process? [ABB]
- Can the Factory help identify application-dependency and geographic-location bottlenecks across data centres? [ABB]

### 4. Performance baselines and sizing

- Which AWR or Statspack reports are available, and what peak days and times should they cover? [ASDA; Schneider — customer on Standard Edition, so AWR may not be available]
- What would the estimated target sizing and cost look like, and does the workload actually fit? [Schneider]
- Which target SKU was chosen, and does it match the source? Recommendation is parity with source initially. [BASF — 64 GB source versus 32 GB requested]
- Which SKU was selected, and why that size — is it for pre-production or production? [Mavriq — M30]
- Should the target disk be sized at least double the source, because source storage is compressed and the target is not? [Mavriq]
- Can quota and regional capacity be checked up front to avoid capacity issues at provisioning time? [BASF]
- For an IaaS-to-PaaS move, can the current environment be analysed to provide exact target cost detail? [ABB]

### 5. Migration tooling

- Which tooling should be used — a native Azure service, or a third-party tool? [ASDA — ADF versus Striim; Holistic AI — DMS versus third-party]
- Is the third-party tool certified and security-cleared, and how long will the cybersecurity review take? [ASDA — flagged as a potential multi-month blocker]
- Is the tool licensing provided free as part of the engagement? [ABB]
- What is first-party tooling versus third-party for schema conversion versus data movement? [ABB]
- Can the replication tool perform online migration with CDC to minimise downtime? [Schneider — Striim]
- Do you use the managed migration service for both online and offline, and native dump/restore for offline? [Holistic AI]
- Should we move off the extension-based approach to a basic offline dump-and-restore? [Mavriq]
- Do you want the offline migration runbook shared? [Mavriq]
- Should there be a follow-up session with a tooling demo? [ABB]

### 6. Migration approach — online versus offline, and downtime

- Is this an online or an offline migration, and which do you want to pursue? [Mavriq; BASF]
- Is the database eligible for online versus offline migration, and are there any blockers? [Holistic AI]
- What downtime window is acceptable for cutover? [BASF — weekends; Mavriq]
- Which option gives the smallest maintenance or offline window during the transition? [Schneider]
- What timeframe is required to move this data volume? [Schneider — ~4 TB]
- What was the migration approach used for the dev environment, and how was it done? [BASF]
- Did the long run time come from transferring the backup, or from the restore itself? [BASF — the restore]
- Is CDC needed to keep production, staging and dev in sync, and how large would the online portion be? [Holistic AI]
- When is the production migration planned? [Holistic AI]

### 7. Schema, data structure and conversion

- How will the schema be created on the target side? [Schneider]
- Should we deploy the application with the new backend, migrate data only, and skip schema conversion? [Schneider]
- Will the application be prepared up front once the schema is migrated, then wait for the data migration? [Schneider]
- What caused the database name clashes when migrating more than one database — is this a schema-versus-database naming issue, or the customer’s own client and domain naming conventions? [Holistic AI]
- How should very large object columns be handled when they exceed what the tooling or target can take in one pass? [Schneider — ~3 TB of log data; maximum and average LOB size queried directly against the source]
- Did we test at document level, database level, or a full cluster restore? [Mavriq]
- Was compatibility checked between the source instance and the target service? [Mavriq]

### 8. Connectivity, access and networking

- Is the source on-premises, in Azure, or elsewhere, and what connectivity route exists to Azure? [Schneider — ExpressRoute]
- Are there devices on the network path, such as application gateways, that could limit throughput? [Schneider]
- What are the networking capabilities of the current data centre? [VINCI]
- What private IP range is used inside the network, and what non-clashing CIDR should be allocated? [Mavriq]
- Is there a firewall rule on the source that only allows traffic from a certain IP range, and does a rule need to be added for the new range? [Mavriq]
- Does the source IP need to be whitelisted on the target service? [Mavriq]
- Can you connect to the target from the source VM, not just from a workstation or IDE? [Mavriq]
- How do we grant the Microsoft team access — guest onboarding into the customer tenant, and a security group request? [ASDA]
- Which environment should be used for the work, and is it free of competing activity? [ASDA — STAG used because SIT was dedicated elsewhere]

### 9. Target platform readiness

- Has the target database server been provisioned, and is a landing zone already in place? [BASF; VINCI]
- Has the production target been provisioned yet, or only dev? [BASF]
- Is the target service already deployed and ready in the subscription? [Holistic AI — Flexible Server deployed]
- Has a target Azure region been decided? [BASF]
- Can you share the subscription ID used for the migration? [BASF]
- Does the Factory recommend separate non-prod and prod subscriptions, or a split by resource group — and is there a customer standard mandating this? [BASF]
- What is the best target for this workload, and will the assessment confirm it? [VINCI — Managed Instance]

### 10. Security, compliance and governance

- Must the tooling installed in the customer environment be assessed by InfoSec first, and can Microsoft connect the customer to the security baseline team? [ABB]
- What is the customer’s security posture — proceed with Defender for Cloud, or use the existing tooling already in place? [VINCI — customer already uses Tenable and Cortex CSPM]
- Has the RACI file been approved by the customer? [CONAD]
- Is the Factory Intake Questionnaire fulfilled, and which milestones are committed for handover? [CONAD]

### 11. Validation and cutover

- Beyond row counts, what validation should be done — for example checksums? [Holistic AI]
- Before cutover, were collection and record counts cross-checked between source and target, allowing for fragmentation differences? [Mavriq]
- Did it copy anything into the target — is any data visible, and what does the activity log show? [Mavriq]
- What is the actual error the migration job reports, before we decide root cause? [Mavriq]
- Is a snapshot or proof of execution needed in the portal for project completion? [Mavriq]
- Will the end-of-engagement Well-Architected assessment be run to surface gaps, recommendations and indicative costing? [VINCI]

### 12. Roles, engagement model and cadence

- How does the Factory operate — what is in scope versus out of scope, is it really free, and what framework is used? [ABB]
- Besides lift-and-shift, are other migration types supported — IaaS to PaaS, or heterogeneous? [ABB]
- Is there extra cost for over-the-shoulder versus full hands-on delivery, and what dependencies could create cost — Copilot licence, AI services, third-party tools? [ABB]
- The customer already works with a systems integrator — how are responsibilities split, and won’t the teams overlap? [ABB — TCS]
- Who is the partner, what is their role versus Microsoft’s, and can the customer get post-migration support for tuning, backup and resiliency or SLA checks? [ABB]
- Can we have a shared live checklist showing what is done and what is next for each meeting? [Holistic AI]
- What cadence should follow-ups take, and should an external Teams channel be created? [VINCI]
- Is a weekly status cadence with progress, blockers and AOB agreed? [ASDA]
- Do you have a tentative timeline for the remaining servers and databases? [Mavriq]
- What is the status of the deal, and are the customer and partner ready to start? [CONAD]

## Questions by engagement

The traceable record. Each engagement lists its route, the sources retrieved with dates and type, and the questions as discussed.

### SCHNEIDER — Oracle 11G to Azure SQL Managed Instance

- **Route:** Oracle 11G → Azure SQL Managed Instance
- **Tooling:** Striim with CDC
- **Volume:** ≈4 TB; one log-history table holds ~90% of the data
- **Team:** Jerzy Lesniak, Siva Kumar S, Prasad Chavan (Microsoft); Nadia Joubert, Todd Miller, Surya Agung (customer and RIB Software)

#### Sources retrieved

| Date | Source | Type |
| --- | --- | --- |
| 2 Jul 2026 | SCHNEIDER / Microsoft — Oracle to SQL DB migration | Meeting transcript |
| 28 Jul 2026 | Weekly Cadence — MoM | Meeting minutes (email) |
| 24–28 Jul 2026 | Weekly Cadence — LOB max size | Email thread |

#### Questions discussed

- Should we deploy the application with a SQL backend, migrate data only, and skip schema conversion — and which migration path should we choose?
- How large is the Oracle database, and what timeframe is required to move that data volume?
- Which option gives the smallest maintenance or offline window during the transition?
- Is the same database shared by multiple customers, or is it one customer per database?
- How will the application side be handled — will the app be prepared up front once the schema is migrated, then wait for the data migration?
- Is the Oracle source currently on-premises, on Azure, or elsewhere?
- What connectivity and access route exists between Azure and the on-premises location?
- Are there any devices on the network path, such as application gateways, that could limit throughput?
- Can Striim perform online migration with CDC to minimise downtime?
- What was the size of the previously migrated database, the 300 GB example?
- Can we split out customers and migrate subsets per customer, instead of the whole database at once?
- Is the data distributed across many tables, or concentrated in a few large ones?
- What would the estimated Azure sizing and cost look like, and does it actually fit?
- Is it acceptable to share the assessment script for the customer to execute and return a report, and is the GitHub repository public?
- Regarding schema, how will the schema be created on the Azure side?
- Do you mean the AWR reports from Oracle — the customer is on Standard Edition, so those may not be available?
- What are the maximum LOB size, average LOB size and sample size on the large log table?
- How should the ~3 TB of log data be handled, given it is too large to migrate in one pass?
- Do you need more information on data migration using Striim and online CDC?
- Should we schedule the next meeting for next week, or reconvene when results are available?

***Why it matters:*** *The 28 July minutes record the project as green, with kickoff, assessment and scope finalisation complete. The open blocker was the 3 TB log volume plus the Oracle 11G legacy version; immediate next steps were provisioning the Managed Instance and preparing the jump box for Striim.*

### ASDA (ToYou) — Oracle to Azure SQL Managed Instance

- **Route:** Oracle → Azure SQL Managed Instance
- **Tooling:** Azure Data Factory preferred over Striim
- **Volume:** ≈250–350 GB
- **Team:** Devendra Bhilare, Siva Kumar S, Prasad Chavan, Bipendra Singh (Microsoft); Mir Hossain, Mayukh Mahanta, Hardeep Giller (ASDA); Jon Willing (Lumen)

#### Sources retrieved

| Date | Source | Type |
| --- | --- | --- |
| 29 Jul 2026 | MSFT — ToYou connect, Factory Meeting Minutes | Meeting minutes (email) |
| 21 Jul – 13 Aug 2026 | Oracle database information gathering | Email thread |
| recurring | ToYou Oracle DB migration — status | Meeting invite and agenda |

#### Questions discussed

- Which migration tooling should be used for the large database — Azure Data Factory or Striim?
- Given the database size, is Striim or SSMA the right tool?
- Is Striim certified and security-cleared, and how long is the cybersecurity review — will it delay the migration by months?
- Should the ~6 GB legacy schema of old signatures be archived rather than migrated, given the data is over 14 months old?
- For the migration assessment, will the DBAs run the information-gathering script following README steps 1–5 and return the output?
- If Statspack reports are required, what peak days and times should they cover?
- How do we grant the Microsoft team access — onboarding accounts as guest users in the ASDA tenant, and raising the security group request?
- Which environment should be used for the work, given the SIT environment is dedicated elsewhere?
- Will a schema-only export generated using Oracle Data Pump work for testing purposes?
- Will a SQL schema dump in the form of a DACPAC extract work?
- Can the target schema already created in Azure SQL Managed Instance be shared?
- What is the standing agenda for the weekly status cadence — progress, blockers, AOB?

***Why it matters:*** *No meeting transcript was retrievable: the ToYou meetings are organised in the external ASDA tenant. Questions come from the 29 July minutes and the information-gathering email thread.*

### VINCI — On-premises SQL Server to Azure SQL Managed Instance

- **Route:** On-premises SQL Server → Azure SQL Managed Instance
- **Scope:** Database component of the ArcGIS service only; 78 databases
- **Team:** Nitin Kerwal, Vinayak Shahapurkar, Jaideep Singh, Santosh Nawadkar (Cloud Factory); Nick Clark, Maxwell Swain, Phelim Grealy (VINCI); Christophe Henriet, Rafik Mazouz (account team)

#### Sources retrieved

| Date | Source | Type |
| --- | --- | --- |
| 6 Aug 2026 | VINCI — MS Factory SQL Migration, Initial Kickoff | Meeting transcript |
| 7 Aug 2026 | MoM — Initial Kickoff, with scope confirmation, service descriptions and Azure SQL MI prerequisites | Meeting minutes (email) |

#### Questions discussed

- Is the source on-premises or virtualised, is the target lift-and-shift or modernisation, what connectivity to Azure exists, and what versions run at source?
- What is the best target for the SQL workload — is a Managed Instance the right destination, to be confirmed by assessment?
- What are the networking capabilities of the current data centre?
- How big is the database, and what is the rate of change or delta volume, so the replication pipe can be sized?
- Is any High Availability — Always On or availability groups — configured?
- Is TDE or encryption enabled?
- Is Azure Arc enabled, so estate details such as versions, collations and patch levels can be shared directly?
- Is the migration scope only the specific in-scope servers, the database-only portion of the service?
- Are there any linked servers, reporting services, or third-party links that could restrict migration?
- Does the SQL assessment show the databases as ready to migrate to Managed Instance, and are the reported blockers at instance level rather than server or network level?
- What is the customer’s security posture — proceed with Defender for Cloud, or use the existing tooling already in place?
- What cadence should follow-ups take — is a weekly sync acceptable, and should an external Teams channel be created?
- Will the end-of-engagement Well-Architected assessment be run to surface gaps, recommendations and indicative costing?

***Why it matters:*** *The richest single kickoff in this set alongside Schneider. The opening question bundles source hosting, target intent, connectivity and versions into one sweep — a good pattern to reuse verbatim.*

### ABB — SQL Server 2016 on-premises to Azure SQL

- **Route:** SQL Server 2016 on-premises → Azure SQL, IaaS and PaaS options
- **Character:** Engagement-model and decision-framing discussion rather than deep technical discovery
- **Team:** Davide Cassiani (organiser), Predrag Jelesijevic, Shawn-xiaoyi Li; systems integrator TCS involved

#### Sources retrieved

| Date | Source | Type |
| --- | --- | --- |
| 1 Jul 2026 | ABB: Support SQL2016 on-prem migration | Meeting transcript |
| 2 Jul 2026 | Following up after ABB: Support SQL2016 on-prem migration | Recap email |
| 6 Jul 2026 | Re: ABB: Support SQL2016 on-prem migration | Email — not individually retrievable |

#### Questions discussed

- Is the SQL 2016 migration project already ongoing, is TCS engaged as partner, and is the plan to complete migration by the end of the calendar year?
- What criteria should decide each database’s path — standard upgrade, full modernisation, or move to PaaS — and what are the pros and cons of each to inform business discussions?
- Which databases are concrete candidates for cloud migration, and is there a finalised candidate list with an ETA?
- How does the Factory operate — what is in scope versus out of scope, is it really free, and what tooling and framework are used?
- Can the Factory help identify application-dependency and geographic-location bottlenecks across data centres, and validate the Azure landing zones already in place?
- Who is the partner or ISD, what is their role versus Microsoft’s, and can ABB get post-migration support for performance tuning, backup and resiliency or SLA checks?
- Besides lift-and-shift, are other migration types supported — IaaS to PaaS, or heterogeneous such as Oracle to PostgreSQL?
- Is there extra cost for over-the-shoulder versus full hands-on delivery, and what dependencies could create cost — GitHub Copilot licence, Azure AI Foundry, third-party tools such as Striim?
- For schema versus data migration, what is first-party tooling versus third-party, and is licensing provided free?
- Since ABB works with TCS, won’t the Microsoft and TCS teams overlap — how are responsibilities split in a RACI?
- If a customer does not fully know their application and SQL Server dependencies, how do we start the migration process?
- Must the automation and agent tooling installed in ABB’s environment be assessed by InfoSec first, and can Microsoft connect ABB with the security baseline team?
- For moving servers from IaaS to PaaS, can Microsoft analyse the current environment and provide exact cost detail for the target servers?
- Should there be a follow-up session with a tooling demo of the Factory’s database migration tools?

***Why it matters:*** *Use this set when the customer is still deciding whether to engage at all. The pros-and-cons-per-path question is the most reusable framing device in the whole bank.*

### BASF SE — AWS RDS MySQL to Azure Database for MySQL

- **Route:** MySQL 8.4 on AWS RDS → Azure Database for MySQL (homogeneous)
- **Volume:** ≈250 GB; ~4 schemas; dev, quali and prod tiers
- **Team:** Rishabh Srivastava, Ruchi Agarwal, Balamanikandan K, Prasad Chavan, Rajat Arora (Microsoft)

#### Sources retrieved

| Date | Source | Type |
| --- | --- | --- |
| 23 Jul 2026 | BASF SE — Database Migration with Factory, kickoff | Meeting transcript |
| 12 Aug 2026 | Weekly cadence | Meeting transcript |
| 23 Jul and 12 Aug 2026 | MOM — BASF SE MySQL Migration | Meeting minutes (email) |

#### Questions discussed

- What was the migration approach used for the dev environment — offline or online — and how was it done?
- Did the long duration come from getting the backup from AWS to the jump server, or from the restoration?
- Can BASF run a Factory-provided assessment script on the source server to capture metadata such as tables without primary keys and large objects — and will it touch or impact production data?
- Is the database version 8.4, and is the same version used across all prod and non-prod environments, matching AWS?
- Was the ~250 GB figure the dev database or the production database?
- Is there only one production server, and is replication or HA — secondary zone, read replica — enabled?
- Has the Azure target database server been provisioned, and is there already a landing zone in Azure?
- Has the production server been provisioned in Azure yet, or only dev?
- How many schemas or databases need to be migrated?
- What is the acceptable downtime window for cutover?
- Was the assessment input workbook filled in and shared along with the output files?
- After the assessment files are shared and reviewed, what are the next steps?
- Has an Azure target region been decided yet?
- Are there only dev and prod environments, or is there a test, stage or QA tier in between?
- Does the “option group membership = MySQL 8.4” column represent the database version, and is that version fine for migration?
- Can you share the Azure subscription ID used for the migration?
- Does the Factory recommend how to set up Azure environments — separate non-prod and prod subscriptions, or a split by resource groups?
- Is there a BASF standard mandating separate non-prod and prod Azure subscriptions?
- The current environment uses 64 GB RAM but the request shows 32 GB — are we downgrading?
- For the chosen region and SKU, can quota and capacity be checked up front to avoid capacity issues?
- Which SKU was chosen for dev, and when is the assessment-report presentation?

***Why it matters:*** *The cleanest homogeneous-migration question set in the bank, and the closest template to reuse for any same-engine move.*

### Holistic AI — Neon PostgreSQL to Azure Database for PostgreSQL Flexible Server

- **Route:** Neon / self-managed PostgreSQL → Azure Database for PostgreSQL Flexible Server
- **Volume:** ≈20–50 GB per database; three to four servers remaining after the first
- **Team:** Prasanth K C (organiser), Prasad Chavan, Vivek Boga, Franklin Fernandez (Microsoft); Raymond Kehoe, Umar Mohammed (Holistic AI)

#### Sources retrieved

| Date | Source | Type |
| --- | --- | --- |
| 19 Jun 2026 | Holistic AI — DB migration status checkin | Meeting transcript |
| 19 Jun 2026 | RE: Holistic AI — DB migration status checkin, MOM | Meeting minutes (email) — not individually retrievable |

#### Questions discussed

- What migration tools are available — is the Azure database migration service the way to go, avoiding third-party tools?
- Why wasn’t the migration automated already — what caused the name clashes when migrating more than one database?
- Is this a schema-versus-database PostgreSQL naming-convention issue, and are the clashes caused by the customer’s own client and domain naming conventions?
- Should we use the Azure migration tool for PostgreSQL Flexible Server, and why did it fail before?
- Do you use the database migration service for both online and offline, and pg_dump and restore for offline native?
- Is the database eligible for offline versus online migration, and are there any blockers?
- Assuming an offline migration of 20–50 GB, what validation can and should be done beyond row counts — for example checksums?
- What does the assessment look for — number of databases, sizes, schema structure, primary keys, large objects, target SKU sizing, and an offline-versus-online recommendation?
- Has the assessment actually been done, and how far did we get — dry run, or one database migrated?
- Is the target PostgreSQL Flexible Server already deployed and ready in the Azure subscription?
- When are we planning the production migration?
- Can we have a shared live checklist and agenda showing what is done and what is next for each meeting?
- Is the domain and name-clash blocker resolved before scaling to the remaining three or four servers?
- Do we need to address online CDC to keep production, staging and dev in sync, and how large would the online portion be?
- Why was there a two-month gap before this blocker was raised — is it recent or long-standing?

***Why it matters:*** *The naming-clash blocker is the transferable lesson: ask early whether the customer’s own database naming conventions will collide on the target platform.*

### Mavriq — MongoDB to Azure Cosmos DB for MongoDB

- **Route:** Self-managed MongoDB 4.2 → Azure Cosmos DB for MongoDB
- **Volume:** ≈5 GB test tier (M30); small collections; POC completed with ~145 documents and zero failures
- **Outcome:** Started online via the VS Code migration extension, hit connectivity blockers, moved to offline mongodump and mongorestore
- **Team:** Yashvant Awasthi, Sundarraj M, Sandeep Nair, Rita Padrao (Microsoft); Mattia Nocerino, Franco Godio, Valerio Coviello (customer side)

#### Sources retrieved

| Date | Source | Type |
| --- | --- | --- |
| 19 May 2026 | Mavriq-Factory Mongo DB — Pre-requisites validation (kickoff) | Meeting transcript |
| 26 May 2026 | VNet peering and connectivity deep-dive | Meeting transcript |
| 16 Jun 2026 | Offline decision and POC sign-off | Meeting transcript |

#### Questions discussed

- Is this an online migration we are trying to perform, and do you want to try offline or online?
- Did you check how much downtime we can afford for the production run?
- Which SKU did you choose, why that size, and is this for pre-production?
- What is the source cluster and source database size?
- How many documents and collections are being copied?
- What is the source cluster version?
- Did it copy anything into the target — did you observe any data migration, any collection or database?
- Can you download the activity and migration log and share it?
- Are you able to run a shell connection from the source VM to the target, not just from the IDE?
- For an online migration we need connectivity between source and target — do we have it?
- Do we need to whitelist the source cluster IP on the target?
- What is the private IP range used inside your network?
- Is there a firewall rule on the source that only allows traffic from a certain IP range?
- What CIDR range do you want — non-clashing, and permitted by the source firewall?
- Do I need to add a firewall rule allowing traffic for the chosen CIDR?
- Where do we find the migration resource that was created, and are we talking about the resource or the service principal?
- What is the TCP proxy, and where do we get it?
- Is the virtual hub a Microsoft service or a third-party service?
- What is the actual error the migration job shows, before we decide the root cause?
- We are moving off the extension to the basic offline approach — dump and restore, correct?
- Did we test at document level, database level, or restoring the entire cluster?
- Did we check compatibility of the instance between the source and the target?
- Should the target SKU disk be sized at least double the source database size, because source storage is compressed and the target is not?
- Before cutover, did you cross-check collection and document counts between source and target, allowing for fragmentation differences?
- Do you have a tentative timeline for the remaining servers and databases?
- Do you want us to share the offline migration runbook?
- Do we need to capture a snapshot or proof of execution in the portal for project completion?

***Why it matters:*** *The only NoSQL engagement with retrievable content. The online-to-offline pivot is the story worth reusing: test connectivity feasibility before committing to an online approach.*

### CONAD — Apps Modernisation and SQL Server Migration

- **Offering:** Apps Modernisation (rehost and re-platform), SQL Server Migration / Oracle or Sybase to SQL
- **Actual scope:** AS/400 modernisation initiative with an Azure AI agent, in partnership with NTT Data
- **Status:** Deal assessment and handover stage — no technical discovery meeting retrievable

#### Sources retrieved

| Date | Source | Type |
| --- | --- | --- |
| 7 Apr 2026 | Microsoft Accelerate Factory — CONAD (Apps Modernisation / Oracle or Sybase to SQL) | Email |
| 24 Apr 2026 | Factory Assessment — Customer: CONAD | Email thread |

#### Questions discussed

- What is the status of the deal, and can we get an update to align with the partner on the SOW and plan resource allocation?
- Are the customer and partner ready to start the project and proceed with next steps?
- Which milestones are in committed state so they can be handed over to the Factory team?
- Is the Factory Intake Questionnaire fulfilled?
- Has the RACI file been approved by the customer?
- Can ECIF and a Factory exception be approved to support the AS/400 modernisation scope?

***Why it matters:*** *Governance questions only. Despite the Oracle-or-Sybase-to-SQL offering label, no technical discovery discussion was retrievable — there is no LOB sizing, collation or cutover content for this account.*

## Coverage and gaps

### Strong coverage — meeting transcripts retrieved

- **Schneider —** 2 July 2026 cadence transcript, plus the 28 July minutes and the LOB sizing email thread.
- **VINCI —** 6 August 2026 initial kickoff transcript, plus 7 August minutes with scope, service descriptions and prerequisites.
- **ABB —** 1 July 2026 meeting transcript, plus the 2 July recap.
- **BASF SE —** 23 July 2026 kickoff transcript and 12 August cadence transcript.
- **Holistic AI —** 19 June 2026 status checkin transcript.
- **Mavriq —** Three transcripts: 19 May kickoff, 26 May connectivity deep-dive, 16 June offline decision and sign-off.

### Partial coverage — minutes and email only

- **ASDA (ToYou) —** No transcript retrievable; the meetings are organised in the external ASDA tenant. Questions come from the 29 July 2026 minutes and the Oracle database information gathering thread.
- **CONAD —** No meeting or transcript found. Only the April 2026 assessment and handover emails, which are governance rather than technical.

### Sources that could not be retrieved

- The individual MoM emails for BASF (23 July and 12 August) and Holistic AI (19 June) could not be opened directly. Their substance is covered by the corresponding meeting transcripts, which are the higher-fidelity source.
- The 6 July 2026 ABB reply could not be opened individually.
- The second 26 May 2026 Mavriq session was inventoried but not read in full; its questions are not included.

### Checked and found empty

Several NoSQL nominations were checked and carry no discussion content — only nomination or enablement records. No questions from these accounts appear anywhere in this document.

- **Sonangol EP —** NoSQL nomination; pre-kickoff invite only.
- **RAI SPA —** GenAI and NoSQL wave 1 nomination; intake call invite only.
- **Abrdn —** Nomination thread; the confirmed scope is VMware to AVS, not a database migration.
- **Schweizerische Bundesbahnen (SBB) —** Nomination correspondence only.

*The remaining NoSQL calendar matches were Microsoft internal enablement events — LevelUp workshops and the weekly SQL, OSSDB and NoSQL sync — not customer engagements.*

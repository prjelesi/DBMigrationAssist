# Banana Inc Customer Example Demo Guide

Use this runbook to demonstrate a realistic Oracle migration assessment with the fictional Banana Inc evidence pack. It complements the broader [three-mode demo](../demo/DEMO_GUIDE.md), which uses Zava to compare Connected, Air-gapped and Standalone operation.

## Demo outcome

By the end of the walkthrough, the audience should see how the toolkit turns an initial estate inventory into evidence-backed migration decisions without treating a preferred target as a predetermined answer.

The Banana Inc story starts with seven production Oracle databases and six dependent application groups. PostgreSQL Flexible Server is assessed first, Azure SQL is the managed fallback, and Oracle on Azure VMs is considered only when application or database constraints block both managed targets.

## Recommended format

| Format | Duration | Coverage |
| --- | ---: | --- |
| Short walkthrough | 12 minutes | Customer story, inventory import, evidence, dependency map and migration waves |
| Full assessment demo | 25 minutes | Short walkthrough plus questionnaires, Oracle findings and report governance |
| Technical extension | 15 additional minutes | Install and assess the runnable Banana Commerce Oracle sample |

## Before the demo

1. Start the platform and sign in as an application administrator:

   ```powershell
   Set-Location C:\github\DBMigrationReady
   docker compose up -d
   Invoke-RestMethod http://localhost:5000/health
   Start-Process http://localhost:3000
   ```

2. Open **Questionnaire** and synchronize the JSON templates if the Oracle and baseline templates are not active.
3. Open **AI Settings** and note whether report readiness is **Connected**. Do not make report generation part of the promised flow unless the connection test succeeds.
4. Decide whether to build the records live or pre-stage them. Pre-staging through the end of **Load the customer** keeps a 12-minute demo predictable.
5. Keep the files in `CustomerExample/evidence` ready for upload. All contents are fictional and presentation-safe.

For a clean local reset, follow the destructive reset warning in the [general demo guide](../demo/DEMO_GUIDE.md#optional-clean-demonstration-environment). Never reset a shared or non-disposable environment.

## Load the customer

### 1. Create the customer and project

In **Projects**, create:

| Field | Value |
| --- | --- |
| Customer | Banana Inc |
| Industry | Food Distribution |
| Region | Northern Europe |
| Project | Banana Inc Oracle Exit |
| Mode | Connected |
| Description | Assess seven production Oracle databases for a managed-service-first migration to Azure. |

Explain that **Connected** records the intended operating pattern. It does not configure customer network controls.

### 2. Create environments

Create these environments before importing the workbook because its rows refer to the production environment by name:

| Name | Type | Location | Connectivity zone |
| --- | --- | --- | --- |
| Banana Primary Datacenter | PROD | Stockholm | On-Premises Production |
| Banana Recovery Datacenter | DR | Gavle | On-Premises Recovery |
| Azure Migration Landing Zone | UAT | Sweden Central | Azure Private Network |

### 3. Import the inventory

1. Open **DB Inventory** and select **Banana Inc Oracle Exit**.
2. Select **Import Spreadsheet**.
3. Upload `CustomerExample/evidence/database-inventory.xlsx`.
4. Confirm that seven Oracle databases were imported.

Use these checks to catch a stale or partial setup before presenting:

- Seven databases: four **Critical** and three **High**.
- Six databases on Oracle 19.x and one, `ora-warehouse-prod`, on Oracle 12.2.0.1.
- Every row belongs to **Banana Primary Datacenter**.
- Owners are populated for all seven rows.

The inventory workbook contains declared customer information, not collector-verified facts. Say this explicitly before showing assessment results.

### 4. Upload supporting evidence

In **Evidence**, select the Banana project and upload:

| File | What it contributes |
| --- | --- |
| `application-database-dependencies.csv` | Application ownership, interfaces, classifications and cutover dependencies |
| `oracle-feature-register.csv` | Initial Oracle feature assumptions and required proof |
| `application-landscape.md` | Application context and target hypotheses |
| `security-and-compliance.md` | Required controls and approval questions |
| `migration-decision-framework.md` | Decision gates, fallback rules and wave principles |

Show the detected source type, parse status and file hash. Describe these files as discovery inputs; labels such as RAC, AQ or VPD remain assumptions until a collector, workshop or authoritative document confirms them.

## Present the assessment story

### Stop 1: Portfolio overview

Open **DB Inventory** and frame the problem:

> Banana Inc wants to leave aging datacenter hardware within 24 months, reduce Oracle cost where practical, and prefer managed Azure services. The estate cannot be assigned one target because vendor support, Oracle coupling, recovery and security differ by workload.

Call out three contrasting records:

- `ora-commerce-prod`: credible PostgreSQL candidate, with PL/SQL and partitioning conversion work to prove.
- `ora-warehouse-prod`: Oracle 12.2, RAC assumptions and a vendor support gate.
- `ora-finance-prod`: Forms, Reports and PL/SQL make application modernization or an interim Oracle rehost more plausible than database-only conversion.

### Stop 2: Dependency and cutover risk

Open **Communication Map**. Add or pre-stage these database-to-database relationships from the dependency register:

| Source | Target | Relationship | Frequency |
| --- | --- | --- | --- |
| `ora-integration-prod` | `ora-commerce-prod` | Order export database link | Every 5 minutes |
| `ora-integration-prod` | `ora-warehouse-prod` | Inventory exchange database link | Every 2 minutes |
| `ora-reporting-prod` | `ora-commerce-prod` | Nightly reporting extract | Nightly |
| `ora-reporting-prod` | `ora-finance-prod` | Financial reporting extract | Nightly |

Use the map to explain why database conversion order is constrained by interfaces. Application-to-database relationships remain in the uploaded dependency register; the communication map focuses on database relationships.

### Stop 3: Questions before conclusions

In **Questionnaire**:

1. Select **Banana Inc Oracle Exit** and **Entire project**.
2. Start or resume **Database Migration Baseline**.
3. Show questions covering business deadlines, RTO/RPO, migration windows, ownership and security approval.
4. Change scope to `ora-commerce-prod` and start or resume **Oracle Migration Assessment**.
5. Show the evidence requests for AWR or Statspack, PL/SQL, partitioning, unsupported objects, downtime, rollback and reconciliation.
6. Save a draft rather than inventing approved answers during the presentation.

Point out that project-wide policy is recorded once while database-specific technical evidence remains attached to the relevant workload.

### Stop 4: Findings and evidence quality

If a Banana Oracle result has been collected, open **Discovery Agents**, select the completed job and expand its findings. Compare collector evidence with the feature register rather than claiming the register was already proven.

Use this evidence language consistently:

- **Declared**: supplied by customer inventory or questionnaire.
- **Observed**: returned by a collector or measured test.
- **Corroborated**: supported by more than one source or reviewed by an owner.
- **Open**: requires evidence or approval before a target decision.

If no live result is available, show the evidence register and make the missing collection an explicit next action. Do not present invented RAC, AWR, object counts or performance values as collector output.

### Stop 5: Migration waves

Open **Portfolio** and create or show these assessment waves:

| Wave | Databases | Reason for grouping |
| --- | --- | --- |
| 0 - Prove and measure | `ora-commerce-prod`, `ora-reporting-prod` | Test PostgreSQL conversion, representative PL/SQL, partitioning, materialized views and reporting performance. |
| 1 - Decouple shared services | `ora-integration-prod`, `ora-customer-prod` | Replace AQ and database links; redesign row-level security and application identity. |
| 2 - Vendor decisions | `ora-warehouse-prod`, `ora-hr-prod` | Resolve vendor certification, source-version and availability gates before selecting a managed target. |
| 3 - Finance decision | `ora-finance-prod` | Align application modernization or replacement with statutory close and reconciliation requirements. |

These are assessment groups, not approved cutover waves. Their purpose is to make dependencies and decision gates visible.

### Stop 6: Report and governance

Open **Reports** and explain that a generated report is grounded in the current findings, questionnaires, evidence, communication edges, portfolio groups and effective report instructions.

- If AI is connected, generate a draft, open its evidence bundle, and show the review and approval states.
- If AI is not connected, show the readiness warning and continue with the assessment artifacts. There is no rules-only report fallback.
- State that a generated recommendation still requires workload-owner, architecture and security review.

## Optional Oracle lab extension

The `CustomerExample/database` folder contains a runnable PeelPay Commerce schema with tables, PL/SQL, triggers, interval partitioning, JSON constraints and deterministic fictional transactions.

1. Install it in a disposable Oracle 19c or 21c schema by following the [sample database instructions](database/README.md).
2. Create a separate **DEV** environment named `Banana Oracle Migration Lab`.
3. Add an Oracle inventory row named `banana-commerce-lab` with the lab host, port, service and version. Do not overwrite the fictional production host merely to make the demo connect.
4. Configure the Discovery Agent's local credential store for that inventory record, or use the offline collector workflow from the general demo guide.
5. Run an Oracle assessment and compare observed objects with the risks documented for `ora-commerce-prod`.

Keep the distinction clear: `banana-commerce-lab` is executable evidence for the demo; it is not an eighth production database in the fictional estate.

## Suggested close

> The Banana example starts with a target preference, but the toolkit forces that preference through application, database, performance, security and operational gates. It keeps assumptions visible, connects evidence to each workload, and turns unresolved constraints into an assessment sequence instead of a premature platform decision.

## Presenter checklist

- [ ] Portal health and administrator sign-in are verified.
- [ ] Banana Inc customer and Connected project exist.
- [ ] Three environments exist before workbook import.
- [ ] Inventory shows seven Oracle databases, four Critical and three High.
- [ ] Dependency and Oracle feature registers are uploaded.
- [ ] Baseline and Oracle questionnaire templates are active.
- [ ] Communication-map edges and assessment waves are pre-staged for a short demo.
- [ ] Any displayed collector output is real output from the disposable lab, not a documented assumption.
- [ ] AI status is known and the report segment matches actual readiness.
- [ ] No passwords, PSKs or non-fictional customer evidence are visible.
# Oracle → PostgreSQL Migration

Consolidated Kickoff & Discovery Questions — Cloud Accelerate Factory portfolio

Prepared for: Predrag Jelesijevic (Cloud Solution Architect)

Compiled: 31 July 2026

Engagements reviewed: Qatar Airways · Manchester Metropolitan University · Essity AB · Tofaş · NHS Wales · AB Volvo · AB SKF · Proximus · Ericsson · CTT Correios de Portugal

*Every question in this document is drawn from a retrieved meeting transcript, minutes of meeting (MOM), or email thread. Nothing has been invented. Where a meeting had no recording, the source is named (agenda, MOM, or email) and any coverage gaps are listed at the end.*

## 1. How to use this document

This pack has two parts. Part 2 is the reusable master question bank — every discovery and kickoff question, de-duplicated and grouped by theme. Reach for it when preparing a new customer kickoff or scoping session. Part 3 is the traceable detail — the same questions as they were actually raised, organized by engagement and by meeting, so you can see who asked what and when.

- Part 2 — Master question bank (by theme): the checklist to run a kickoff / discovery.
- Part 3 — Questions by engagement (by meeting): the source record, with dates and source type.
- Part 4 — Coverage & gaps: which meetings had transcripts vs. minutes/email, and which engagements are still at nomination stage.

## 2. Master question bank (by theme)

A consolidated, de-duplicated set of the questions that recurred across the portfolio. Use as a kickoff / discovery checklist.

### 2.1 Scope & objectives

- Is the engagement database migration only, or does it also include application (code / syntax) migration?
- Which applications and databases are in scope for this wave, and what is deferred to later waves?
- What is the target end-state and business driver (e.g., exit Oracle by a fixed date; move off a “burning platform” such as AIX)?
- Is application-layer Oracle→PostgreSQL syntax conversion within Factory scope, or does it need separate / partner expertise?
- Which workloads can modernize to PostgreSQL, and which must stay on Oracle (Oracle Database@Azure / marketplace)?

### 2.2 Current environment & discovery

- What is the current database landscape (Oracle version — 12c / 19c, SQL Server, PostgreSQL, others)?
- What are the application dependencies and integration points?
- What are the hosting details — on-prem, OCI, Azure, or hybrid?
- Is Oracle Exadata in use, and are those versions supported for migration into Azure?
- What is the full inventory of databases / servers, and how does it split across prod vs. non-prod?
- Which vendor supports each database, and will they support PostgreSQL (or is Oracle@Azure the fallback)?

### 2.3 Assessment & info-gather scripts

- Does the assessment / metadata script run against the whole database?
- Will the script affect any object, transaction, data, or process?
- Can the script be run with a read-only user?
- Does the script send any data online, or is it purely offline — and how are results returned?
- Does it extract only metadata / object counts and types (no sensitive or structural data)? (customer security review)
- Will the customer run the scripts and hand back output, or will Microsoft run them — and does the customer want to review the script first?
- How does the script connect to a pluggable database (CDB / PDB) — the root container or the PDBs directly?
- Have prerequisites been completed (open ports, access, target PostgreSQL server created, Java 17, connectivity tested)?

### 2.4 AWR / Statspack & target sizing

- Have AWR (or Statspack) reports been provided, and for which servers (production and test)?
- What time period should the AWR cover — 30 days, or shorter windows across peak hours?
- Will the assessment also determine compute power / SKU equivalency for the target?
- How many PostgreSQL servers / instances are needed to host the Oracle databases?
- Should databases migrate “as is” (one DB per server) or be consolidated (multiple per server), and what are the cost / sizing implications?

### 2.5 Migration approach & tooling

- Which tool / approach — Striim (CDC) vs. Ora2Pg vs. the VS Code PostgreSQL extension — given database size and schema / object complexity?
- Online vs. offline migration mode?
- Which objects cannot be migrated automatically (wrapped / encrypted packages, synonyms, directories) and must be re-coded?
- How do we handle tightly-coupled schemas with cross-schema dependencies — must the whole database migrate together?
- Which VS Code version and extensions are required?
- How are schema-name and table mismatches between source and target reconciled?
- Does the tool provide confidence / QA of zero data loss?

### 2.6 Downtime & cutover

- Can the migration be achieved with minimal / zero downtime?
- What downtime window can each application owner afford?
- Is a POC (on non-prod / Dev / UAT) required first, then production cutover?
- After the POC, is the cutover feasible, and how do we shorten an over-long migration window?
- What is the production cutover target date, and what business / seasonal constraint drives it?

### 2.7 Connectivity & access

- Does connectivity (VPN / ExpressRoute) exist between on-prem / OCI and Azure; if not, what is the plan?
- Are firewall / NSG rules in place for the jump host → database, and for OCI ↔ Azure?
- Is remote access via VDI / jump host set up, and are the Factory (offshore) users’ static IPs whitelisted?
- Are the required credentials / privileges available (system / sys to reset passwords, run scripts, register the listener)?
- Where are the Oracle client and TNS file installed?

### 2.8 Security, governance & compliance

- Where does data land during migration — does it stay in the customer tenant (e.g., Striim installed on a customer-owned VM)?
- Is data at rest on Azure PostgreSQL encrypted (Microsoft-managed vs. customer-managed key)? Is TLS enabled by default for data in transit?
- Has the security / DPIA checklist (and data-flow diagram) been completed, and which questions actually apply to the tool?
- Will Information Governance approve the migration tool for production use with clinical / sensitive data?
- Can the AI component in the tool be disabled so it is not used for data transfer?
- Is Microsoft Defender for Cloud to be enabled, and is it in scope?
- Do all new resources meet the Azure Secure Score framework (Entra-only auth, pgaudit logging, log retention, Network Watcher) — now, or hardened after the PoC?

### 2.9 AI & licensing prerequisites

- Is a GitHub Copilot (Business / Enterprise) license available for the AI-driven schema / app conversion?
- Is the required Azure OpenAI model available in the customer’s approved regions; if not, is an exception needed?
- Is an Azure OpenAI endpoint / AI Foundry consumption available, and who funds the AI cost?
- Has the Striim license been procured, is it perpetual or annually renewed, and does it cover through go-live?
- Who provides tooling licenses for local / partner laptops — the customer or the partner?

### 2.10 ROI / TCO / commercial

- What is the ROI / TCO of Oracle (contractual license cost) vs. PostgreSQL?
- What data points are needed to calculate the PostgreSQL cost estimate (DB size, CPU, query counts)?
- Should the ROI / business case be settled before security / GRC approvals proceed?
- Will Microsoft fund the migration cost (AI, credits, resourcing), and how?
- What is the migration effort and duration given the data size (e.g., ~10 TB)?

### 2.11 Roles, ownership & delivery model

- Does the customer want “over-shoulder” (guided) or “hands-on” (Factory-executed) delivery?
- Who runs the assessment scripts, and who owns portfolio triage (the PostgreSQL vs. Oracle@Azure decision)?
- Who supports each database, and will they approve the move to PostgreSQL?
- When and how do we align with — and get approval from — application and database owners (ITSOs) before migrating?
- Who from the customer provides application / database details — the named contact or the app team?

### 2.12 Timeline, governance & logistics

- What is the tentative project timeline and POC end date, and does it align to the customer’s?
- What is the meeting cadence, status reporting, and RAID / issue-tracking approach?
- What is the mode of execution — screen share or remote access?
- Who attends from each side, and are there upcoming leave dates affecting scheduling?
- What are the next steps and prerequisites to confirm before the next session?

## 3. Questions by engagement

The same questions as actually raised, grouped by engagement and by meeting. Source type (transcript, minutes/MOM, agenda, or email) and date are named under each heading.

### 3.1 Qatar Airways

Migrate the Horizon application database from Oracle to Azure PostgreSQL Flexible Server; goal to exit Oracle by end of CY27. Wider opportunity ~208 servers / ~68 workloads.

#### Wave 1 Kickstart — 28 July 2026

*Source: meeting transcript (calendar subject “Follow-up: Qatar Airways: Oracle to PostgreSQL”; documented in the MOM as the Kick-start).*

- What open queries must the team resolve to kick the project off, and what is the overall scenario?
- Can we produce a granular ROI / cost-benefit for Horizon (beyond the ~70% Uber-level figure) that extrapolates to other applications?
- Can Microsoft complete the security / DPIA checklist so Cyber GRC can approve access to AI resources?
- Is Azure OpenAI GPT-5.2 available in QR-approved regions? If not, an exceptional Cyber GRC approval with justification is needed (access is via the Microsoft Postgres plugin, not GitHub Copilot).
- For data migration, what is the effort and how long will it take — and how will resources / AI cost be funded?
- What is the ROI of Horizon on Oracle vs. PostgreSQL, and what does Microsoft need to calculate the Postgres cost — just DB size, CPU, and query counts?
- Should the ROI be settled before Cyber GRC approvals (decide the business case first)?
- After the POC, is cutover feasible, and if the migration window is too long, how do we bring it down?
- Source is on-prem Oracle → Postgres; a POC on Dev / UAT is required first (timing depends on network, DB size, schema complexity) — correct?
- We need the output of the info-gathering script to build the assessment — environment size, and whether any extensions or DB links are used and PostgreSQL-compatible.
- Can your team (and Microsoft) confirm the scripts export only object counts / types — no sensitive, structural, or user data?
- Will you review the script and tell us which checklist questions actually have to be filled out (most are not applicable to the tool)?
- Which environment hosts this — is it currently in Qatar Airways? And will we use the VS Code (PostgreSQL) extension for the assessment?
- Are you the right person to get application / database details, or does that need the application team?

#### Internal Factory sync-up — 23 June 2026

*Source: internal Microsoft / Factory meeting transcript.*

- What will be the mode of execution — screen sharing or remote access?
- What is the POC planned end date for the first server (June-end vs. July-end)?
- Do they have both non-prod and prod environments (plan to start with non-prod)?
- Do they need our help to run the assessment script, or will they run it and hand us the output?
- Did we share the prerequisites document so they are ready with access / open ports?
- Do we have the intake answers — which database is identified for the POC, Oracle 19c vs. OCI, and what environment they have?
- Do we have the customer contact to schedule the Kickstart meeting?

#### TCO / ROI and commercial prerequisites — email thread (Apr–Jun 2026)

*Source: email thread (the 25 June TCO meeting and 16 June follow-up had no transcript).*

- Confirm Azure OpenAI GPT-5.2 (or higher) is available in QR-approved regions — and if not, note the exceptional Cyber GRC approval required (DPIA + data-flow diagram).
- For data migration (Striim licenses), what is the effort for setup, configuration, review, and integrity scripts (~10 TB)?
- What is the expected duration (in hours) to have the data migrated?
- Confirm the overall migration cost — AI cost, GitHub Copilot AI credits, and human resourcing — will be funded by Microsoft, and advise how.
- The tooling is free but needs a GitHub Copilot license and an Azure OpenAI endpoint — do you have it or can you get it approved?

### 3.2 Manchester Metropolitan University (MMU)

Oracle → PostgreSQL (and Oracle-on-Azure for apps that cannot move); AIX is the “burning platform” to decommission first.

#### Kickoff — 30 June 2026

*Source: meeting transcript + circulated agenda. (The 15 June workshop was on an external tenant and the 1 June nomination call had no transcript.)*

- With Striim (third-party tool), does data land on the Striim platform, or does it install locally on an MMU-owned VM so data stays with MMU?
- Does Striim need a separate box or can it sit on the existing jump box, and what are its prerequisites (Azure VM vs. on-prem, Linux vs. Windows, CPU / memory)?
- Is data at rest on Azure PostgreSQL encrypted (Microsoft-generated vs. customer-managed key)? Is network / TLS encryption on by default for data in transit?
- Backup & restore: to restore a single database must you restore the whole server first, or is there a per-database approach (vs. current RMAN / Rubrik)?
- How many PostgreSQL servers / instances are needed for the multiple Oracle DBs (Windows and Linux), and will the assessment also assess compute / SKU equivalency?
- One instance per database vs. consolidating archive vs. live DBs — what is Microsoft’s recommendation (weighing firewall-rule management and cost)?
- What exactly are the steps to start the assessment — which scripts run against what, and what do we hand back (script output + AWR / Statspack per instance)?
- The app vendor is thesis (not Unit4); will thesis support PostgreSQL, or are these DBs candidates for Oracle on Azure instead?
- How do we get started onboarding Oracle via the Azure Marketplace without committing to unclear terms — can we get concrete steps and a POC of importing the QLLIVE dev DB, with an Oracle expert assigned?
- Concerns raised on timescales and costs; can the AIX student workload use the same archiving tool as SAP to take it out of scope?
- Config for the Striim VM — Azure VM only? Linux or Windows? (Microsoft to MMU)
- Who will attend from MMU, and are there upcoming annual-leave dates affecting scheduling? (Microsoft to MMU)

#### Assessment inventory — email thread (Jul 2026)

*Source: “MMU Oracle to PostgreSQL assessment” emails.*

- Have the pre-reqs been set up by the MMU cloud team to enable the initial DB compatibility assessments?
- Populate three inventory columns — Apps used by database, Known DB Integrations, Support details — to answer: will each app need changes when its database migrates, or must the app move with it?
- Can you clarify the purpose of the Support Details and Destination columns? (Destination stays TBD until the technical + support assessment is done.)
- Are Statspack reports available for all servers if AWR is not? (needed to prepare the assessment report)

### 3.3 Essity AB

CAF nomination — Oracle → PostgreSQL and application migration, Wave 1. Oracle ~19c on AIX; ~1–1.5 TB per region (to be confirmed).

#### Internal kickoff — 1 July 2026

*Source: meeting transcript + minutes (MOM) + agenda.*

- Are they planning the database migration first, or targeting the application at a later stage?
- Is application-level / syntax conversion in Factory scope at the database layer, or does it need separate expertise?
- What is the underlying application platform — .NET or Java?
- What is the target architecture — already decided by the customer, or to be finalized — and where do they want to deploy?
- Is the target platform EnterpriseDB vs. Azure PostgreSQL Flexible Server (Horizon DB vs. Flexible Server) — still open?
- Does connectivity (VPN / ExpressRoute) already exist between on-prem and Azure; if not, what is the plan?
- Does the customer run Oracle Exadata? (flagged to confirm)
- What is the size of the database — do we have it? (~1–1.5 TB per region, to confirm)
- Does the customer plan to enable Defender for Cloud, or must we check with them?
- For the customer session, do we also do a short Factory introduction / methodology walkthrough, or leave it to a later session?
- Who needs to attend from the Factory side, and has the customer session been scheduled?

### 3.4 Tofaş

Ora2PG Factory migration (Koç Holding). Kickoff 14 May 2026, then recurring assessment-validation calls.

#### Kickoff — 14 May 2026

*Source: meeting transcript + minutes (MOM).*

- Is the VDI connection problem at the VDI layer, or network / virtualization — and are the Factory (India / France) users’ static IPs whitelisted?
- Do you have a tentative timeline to complete the project, so we can align to it?
- Where does the AI support fit into the migration steps?
- Will you convert all objects — procedures, packages, functions — from Oracle to PostgreSQL, or re-code them on the new side?
- Confirm unsupported objects: encrypted (wrapped) packages cannot be migrated, and directories / synonyms have no PostgreSQL equivalent — correct?
- Our Oracle DB is huge with complex, mutually-dependent schemas — how do we approach migrating tightly-coupled schemas; must the whole database migrate together?
- Does the assessment script run against the whole database?
- Will the script affect any object, transaction, data, or process?
- Can we run the script with a read-only user?
- Does the script send any data online, or is it purely offline — and how do we return the results to you?
- Don’t we need the schema’s resource consumption (AWR) to size the destination PostgreSQL (CPU / memory), given it is one schema out of 250+ in the instance?

#### Follow-ups & security posture — email threads (Jun–Jul 2026)

*Source: walkthrough MOM + Secure Score email threads.*

- Decide online vs. offline migration mode (online via Striim vs. offline).
- Which Secure Score items need immediate action — Entra-authentication-only on the PostgreSQL flexible server, and Network Watcher enabled?
- Additional findings to action: pgaudit.log should include role/ddl/misc; pgaudit.log_statement_once = on; log retention > 3 days.
- Can we keep PoC environment requirements to the minimum during the PoC, then harden to Tofaş Secure Score standards afterwards — is that acceptable? (open feedback request)

### 3.5 NHS Wales Informatics Service

Oracle 12c → Azure PostgreSQL Flexible Server (DHCW). Tooling: VS Code PostgreSQL extension for schema; Striim (CDC) for data. Clinical data — Information Governance in scope.

#### Kickoff / intro — 22 May 2026

*Source: minutes (MOM) only — no transcript. Framed as risks / dependencies / assumptions.*

- Can the migration be achieved with minimal / zero downtime (business cannot accommodate significant outages)?
- Is the current Ora2Pg approach acceptable given it causes a significant outage?
- Will the Striim + CDC approach meet the low-downtime requirement (to validate via POC)?
- Will Information Governance approve Striim for production, given clinical data is involved?
- Has the Striim license been procured / requested?
- Is there sufficient Azure UK South capacity?
- Will DB-level business-logic refactoring (moving logic to the app layer) complete before cutover?
- Which POC environment will the customer finalize, and will they run the metadata scripts and provide AWR reports for sizing?

#### Assessment presentation — 3 July 2026

*Source: meeting transcript + minutes.*

- Is the production source memory correct at ~1110 GB (the box actually has 1500 GB)?
- Is the non-prod schema already migrated (so only non-prod data remains)? When we go to production, do we start both schema and data?
- Are those VM sizes for the Striim VM or for the Postgres Flexible Server?
- Which tables currently use BLOBs (is the large “documents” table in scope)?
- Does the tool provide confidence of zero data loss / QA validation?
- Are we doing a POC, and on non-production only — does the POC-then-production approach sound sensible?
- What is the tentative POC timeline (VM must be provisioned first), and are we licensed and ready to go?

#### Follow-up — 23 July 2026

*Source: meeting transcript + minutes.*

- Any progress on the Striim part / source & target connectivity — status?
- We need assurance the AI component in Striim will be disabled and not used for data transfer — is Striim using AI when transferring data?
- Confirm data moves directly on-premise → Azure with no intermediary, and the Striim VM stores no data (logging only)?
- Have you started procuring the Striim server / what is the VM readiness — anything stopping us repurposing a POC VM to host Striim?
- Will you guide our developers to configure / install Striim, or do it yourselves — and support Christian / Christopher on the VS Code schema runs?
- Will the recommended PostgreSQL target SKU / size come out of this work, and do you need the AWR reports resent (which servers)?
- Are the Striim licenses perpetual (usable after go-live), or is there annual renewal / cost — and has the license been received?
- Do you expect to close in July, or will it slip? (POC by November, production cutover ~February, driven by the vaccination-campaign window)

### 3.6 AB Volvo / Volvo Group

Central IT owns ~200–300 Oracle databases; lead with PostgreSQL modernization, Oracle@Azure only where PostgreSQL is not viable. No transcript available (the CSA was not a participant); items below are from the email thread, internal chat, and planned agendas for the 17 / 19 August sessions.

#### Planned agenda & discovery — email + internal prep (Jul–Aug 2026)

*Source: email thread and internal prep notes — planned / to-be-discussed questions.*

- Review of the AWR report (snapshot 2 July) — what do the Oracle performance metrics imply for the target design and infrastructure requirements?
- Is the proposed Oracle 19ai/29ai → PostgreSQL architecture design sound? (Volvo to present, Microsoft to give feedback)
- What are Microsoft’s offerings for running the central IT department’s ~200–300 Oracle databases on Azure, and how do we accelerate migrations via Factory?
- Which workloads can modernize to PostgreSQL, and which cannot (and therefore need Oracle@Azure)?
- How do we migrate the JD Edwards workload off the (unsanctioned) Oracle IaaS Cloud to Azure CEP now that it is ready to decommission?
- Is the prior gap in Azure CEP services (offering Oracle Databases on Azure CEP) now resolved, and how?
- How do we get started and reach a concrete plan / roadmap, and who are the right stakeholders to engage?

### 3.7 AB SKF

Oracle → PostgreSQL Flex across OCI / Azure. Large estate (19 non-prod + 20 prod servers, 600+ DBs); POC on 2 DBs first.

#### Working session — 22 July 2026

*Source: meeting transcript.*

- Will the info-gather script run from Linux, is the input.csv required, and does it need blank rows removed / approval-status = yes?
- How will the script connect to a pluggable database — the root container, or does it detect CDB / PDB and connect to the PDBs?
- Is only one server in scope, or more — and what are the IP addresses and DB names of the other servers?
- For the AWR report, what period is needed — 30 days, or multiple shorter reports covering peak hours?
- Can you manually run and share the number of schemas and databases per instance (the automated output looked truncated)?
- Will this be an online migration, and does online vs. offline depend on database size and the downtime the app team can afford?
- Once the migration plan is shared, how / when do we align with application owners and get approval from application & database owners / ITSOs before migrating?
- Can production server details be pulled alongside the POC report so assessment happens in one pass?
- There are ~40 databases — must every step run on every database, or can it be batched from a jump host with connectivity to all?
- Where should the VS Code extension and Striim tools be installed, and are there step-by-step instructions? Prereqs: Java 17, an Oracle connection ID, target Postgres server created and tested.

#### Weekly cadence / access troubleshooting — 20 July 2026

*Source: meeting transcript.*

- Is access fully set now — any blockers?
- Will the web-app software license for the local (TCS) laptop be provided by SKF, or will TCS procure it?
- Is the Azure VM reachable via Bastion (console vs. OS login), and is G-Scaler / CA-PAM actually needed?
- Do we have the private key (as a .ppk) to SSH to the Oracle server, and are NSG rules created on the OCI side for the jump-host → database connection?
- Does anyone have OS (root / OPC) access to register the service with the listener, and do we know the default password?
- Why can no user connect to the pluggable database after a password reset — password-policy / special-character issue, locked account, or profile restriction? Should we create a new minimal-privilege user?
- Where is the Oracle client installed and where should the TNS file be placed?

#### Initial kickoff & cadence — minutes (May–Jul 2026)

*Source: MOM emails (4 May kickoff, 18 May, 13 July).*

- Do migrations require downtime or can they be done online (downtime windows depend on app owners)?
- Do databases migrate “as is” (one DB per server) or consolidated (multiple per server) — and what are the cost / sizing implications?
- What network connectivity / firewall openings are needed for the assessment script to reach all DBs (OCI first, then Azure / on-prem)?
- How do we split the 600+ DB inventory into 3–4 tracks / waves, and which DBs to prioritize?
- Which Microsoft-side user IDs are needed for access provisioning, and are there requirements beyond user IDs? Validate OCI ↔ Azure connectivity.

### 3.8 Proximus

FY27 Oracle migration plan, CAF involvement. ~2,800 Oracle databases; three paths — ODAA, Lift & Shift IaaS on OCI, and PostgreSQL modernization.

#### CAF involvement — 24 June 2026

*Source: meeting transcript + planning email.*

- Can CAF confirm what is possible for the planned activities — ODAA, Lift & Shift IaaS OCI, and PostgreSQL modernization?
- Can the tooling / process also be used just for an assessment, since not all of the Oracle estate will fit PostgreSQL modernization?
- How would this be approached for the ~2,800 databases when it isn’t yet known which fit PostgreSQL vs. marketplace / ODA?
- What is the decision parameter to choose PostgreSQL vs. ODA / marketplace per app / database (e.g., can the application code be changed)?
- Where does responsibility for assessment / portfolio triage sit — CAF provides non-committing tooling while the customer / partner owns the decision, then CAF executes?
- Does the customer want “over-shoulder” (guided) or “hands-on” (CAF-executed) delivery?
- Is it reasonable to require the customer to provide their own AI licensing (GitHub Copilot Business / Enterprise + Azure AI Foundry consumption), since schema / app migration is AI-driven?
- Are the specific Oracle / Exadata versions supported to complete the migration into Azure? (Global Black Belt to verify the DB list)

### 3.9 Ericsson

Oracle 19c → Azure PostgreSQL Flexible Server (Postgres 16) with Striim + the VS Code migration extension; 8 databases across three Oracle instances. Completed (“Win Wire” circulated 28 July 2026). The richest source — the 27 February prerequisite-discussion transcript — sits on an external organizer’s mailbox and could not be retrieved.

#### Kickoff / planning sync — 20 February 2026

*Source: AI meeting recap (summary + action items), not a verbatim transcript.*

- Is the scope database migration only, or does it include application migration? (clarified as database-only)
- What are the prerequisites (licensing and infrastructure) to start, and can the migration meet the early-June deadline given licensing constraints?
- Which VS Code version and extensions are required, and what are the Striim tool prerequisites (runbook requested)?
- What does the AWR report show for peak workload hours (to size the target PostgreSQL), and what does the current architecture look like?
- Is a GitHub Copilot subscription / license available, and is the licensing feasible without blocking the timeline?

#### Working sessions & licensing — chat + email (Feb–Jul 2026)

*Source: project chat and Striim license email thread.*

- AI is now part of the conversion (requires Azure OpenAI) and the VS Code extension depends on a GitHub Copilot license — how do we resolve the licensing dependency?
- Will Azure consumption change based on the data migrated, or stay in line with the initial plan (three instances → three PostgreSQL servers)?
- For the slowness / lag: are source, Striim, and target in the same network region, and what is the current vs. expected rate (events/sec)?
- Schema-name differences and a table present in Oracle but missing in PostgreSQL — how should these be mapped / reconciled?

### 3.10 CTT – Correios de Portugal

Oracle → PostgreSQL Flexible Server (Waves 4 & 5), partner Unipartner. Nomination / intake stage only — no kickoff has been held or transcribed. Items below are planned agenda / prerequisites from the nomination emails.

#### Nomination & intake — email thread (Jul 2026)

*Source: nomination / intake / approval emails — planned, not yet discussed.*

- Microsoft Defender for Cloud (Wave 4) — to be discussed with the customer at kickoff and proceeded with accordingly.
- Confirm in-scope vs. out-of-scope activities during the Scoping stage (out-of-scope items route to support outside the Factory).
- Complete the Factory Intake Questionnaire (the detailed discovery question set lives in the Power Apps form).
- Commit milestones for Wave 4 & Wave 5 to convert provisional approval to full approval and assign the delivery team.

## 4. Coverage & gaps

Where the questions came from, and what could not be retrieved:

- Qatar Airways — transcripts for the 28 July Kickstart and 23 June internal sync; the 25 June TCO and 16 June follow-up had no transcript (used minutes / email).
- Manchester Met — transcript for the 30 June kickoff; the 15 June workshop (external tenant) and 1 June nomination call had no accessible transcript (used agenda / emails).
- Essity AB — transcript, minutes, and agenda for the 1 July internal kickoff; the 2 July customer session was not retrievable.
- Tofaş — transcript for the 14 May kickoff; follow-ups covered via minutes and the Secure Score email threads.
- NHS Wales — transcripts for 3 July and 23 July; the 22 May kickoff was minutes-only.
- AB Volvo — no transcript (CSA not a participant); questions are planned-agenda items from email and internal prep for the 17 / 19 August sessions.
- AB SKF — transcripts for 22 July and 20 July; minutes for the 4 May kickoff, 18 May, and 13 July.
- Proximus — transcript for the 24 June session plus the planning email.
- Ericsson — no accessible transcripts (external organizers); used the AI recap of the 20 February kickoff, nomination / licensing threads, and the working chat. The 27 February prerequisite transcript exists but is locked to an external mailbox.
- CTT Correios — nomination / intake stage only; no kickoff held or transcribed yet. The detailed discovery questions will come from the Factory Intake Questionnaire and the first scoping session.

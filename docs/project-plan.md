# DB Migration Readiness Assessment Tool — Project Plan

**Project:** DBMigrationAssist  
**Repository:** https://github.com/prjelesi/DBMigrationAssist  
**Owner:** prjelesi  
**Start Date:** 2026-07-21  
**Status:** 🟡 In Progress

---

## 1. Executive Summary

DBMigrationAssist is a self-contained database migration readiness platform that enables customers and Microsoft engineers to assess database estates for migration to Azure. It combines:

- A **Power Apps Canvas** front-end for questionnaire input and bulk database inventory upload
- A **Docker-containerised assessment engine** that runs the Azure Cloud Accelerate Factory info-gather scripts and scores readiness
- **Dataverse** as the shared data store for assessment results
- A **Copilot Studio agent** that consumes assessment results and generates natural-language migration plans and reports

---

## 2. Architecture Overview

```
┌──────────────────────────────────────────────────────────────────┐
│  Power Apps Canvas App                                           │
│  • DB inventory form  • Bulk CSV upload  • Results dashboard     │
└────────────┬─────────────────────────────────────────────────────┘
             │ Power Automate (Submit + Poll + Callback)
             ▼
┌──────────────────────────────────────────────────────────────────┐
│  Docker Container  (runs in customer environment)                │
│  FastAPI REST API                                                │
│  POST /assess  |  POST /assess/bulk  |  GET /status  |  GET /report │
│  ──────────────────────────────────────────────────             │
│  Invoke-Assessment.ps1  →  Factory Scripts (6 DB types)         │
│  pwsh + psql + mysql + mongosh + az cli                         │
└────────────┬─────────────────────────────────────────────────────┘
             │ Dataverse Web API (Service Principal)
             ▼
┌──────────────────────────────────────────────────────────────────┐
│  Microsoft Dataverse                                             │
│  cr_assessmentrun  |  cr_assessmentitem  |  cr_dbinventory      │
└────────────┬─────────────────────────────────────────────────────┘
             │
             ▼
┌──────────────────────────────────────────────────────────────────┐
│  Copilot Studio Agent  —  "Migration Readiness Advisor"         │
│  • Assessment summaries    • Wave migration plans               │
│  • Blocker resolution      • Export to Word / Email             │
└──────────────────────────────────────────────────────────────────┘
```

### Supported Migration Paths

| Source | Target | Type |
|---|---|---|
| SQL Server 2008–2022 | Azure SQL DB / MI / VM | Homogeneous |
| PostgreSQL 9.5–16 | Azure DB for PostgreSQL Flexible | Homogeneous |
| MySQL 5.6–8.4 | Azure DB for MySQL Flexible | Homogeneous |
| MariaDB 10.x–11.x | Azure DB for MySQL Flexible | Homogeneous |
| MongoDB 3.6–7.0 | Azure Cosmos DB for MongoDB | Homogeneous |
| Cassandra 3.11–4.x | Azure Managed Instance for Cassandra | Homogeneous |
| Oracle 11g–21c | Azure DB for PostgreSQL / Azure SQL | Heterogeneous |

---

## 3. Phases & Milestones

### Phase 1 — Foundation ✅ Complete

| # | Task | Status | Owner |
|---|---|---|---|
| 1.1 | Project structure and GitHub repo setup | ✅ Done | prjelesi |
| 1.2 | Download & extract all Factory info-gather scripts (6 DB types) | ✅ Done | prjelesi |
| 1.3 | Build `migration-paths.json` — all 8 paths with factory script refs | ✅ Done | prjelesi |
| 1.4 | Build `questionnaire.json` — 20-question assessment (5 sections) | ✅ Done | prjelesi |
| 1.5 | Build `scoring-matrix.json` — readiness bands, effort multipliers | ✅ Done | prjelesi |
| 1.6 | Build `Invoke-Assessment.ps1` — orchestration + scoring engine | ✅ Done | prjelesi |
| 1.7 | Sample inventory CSV + validated end-to-end test | ✅ Done | prjelesi |

---

### Phase 2 — Docker Assessment Engine 🟡 In Progress

| # | Task | Status | Owner | Est. Days |
|---|---|---|---|---|
| 2.1 | `Dockerfile` — Ubuntu + pwsh + DB clients + FastAPI | ✅ Done | prjelesi | 0.5 |
| 2.2 | `docker-compose.yml` + `.env.example` | ✅ Done | prjelesi | 0.5 |
| 2.3 | FastAPI REST API — `/assess`, `/status`, `/report`, `/bulk` endpoints | ✅ Done | prjelesi | 1 |
| 2.4 | Dataverse push — MSAL auth + `cr_assessmentrun` + `cr_assessmentitem` | ✅ Done | prjelesi | 1 |
| 2.5 | Docker build test and local validation | 🔲 TODO | | 1 |
| 2.6 | Integration test: submit sample CSV → poll → verify report in output | 🔲 TODO | | 0.5 |
| 2.7 | Network exposure strategy (ngrok / Azure Relay / internal DNS) for Power Apps reach | 🔲 TODO | | 1 |

**Phase 2 Exit Criteria:** Container builds clean, `/assess` returns scored report, Dataverse receives records.

---

### Phase 3 — Dataverse & Power Platform Setup 🔲 Not Started

| # | Task | Status | Owner | Est. Days |
|---|---|---|---|---|
| 3.1 | Create Power Platform environment / solution (`DBMigrationReadiness`) | 🔲 TODO | | 0.5 |
| 3.2 | Create Dataverse tables from `dataverse/tables.json` schema | 🔲 TODO | | 1 |
| 3.3 | Register Service Principal (Entra ID App Registration) for API→Dataverse auth | 🔲 TODO | | 0.5 |
| 3.4 | Import Custom Connector from `connectors/openapi.json` | 🔲 TODO | | 0.5 |
| 3.5 | Test Custom Connector against running Docker container | 🔲 TODO | | 0.5 |
| 3.6 | Build Power Automate flow: `Submit_Assessment_from_PowerApps` | 🔲 TODO | | 1 |
| 3.7 | Build Power Automate flow: `Export_Assessment_Report` | 🔲 TODO | | 1 |

**Phase 3 Exit Criteria:** Power Automate flow successfully submits to Docker, polls status, and Dataverse shows completed records.

---

### Phase 4 — Power Apps Canvas App 🔲 Not Started

| # | Task | Status | Owner | Est. Days |
|---|---|---|---|---|
| 4.1 | App skeleton — screen navigation, theme, branding | 🔲 TODO | | 1 |
| 4.2 | Screen 1: Welcome / Customer name input | 🔲 TODO | | 0.5 |
| 4.3 | Screen 2: Single database assessment form (questionnaire) | 🔲 TODO | | 2 |
| 4.4 | Screen 3: Bulk CSV upload + preview grid | 🔲 TODO | | 1.5 |
| 4.5 | Screen 4: Submission progress / polling indicator | 🔲 TODO | | 1 |
| 4.6 | Screen 5: Results dashboard — score cards, band colours, blocker list | 🔲 TODO | | 2 |
| 4.7 | Screen 6: Per-database drill-down — findings, effort, tools | 🔲 TODO | | 1 |
| 4.8 | Screen 7: Report export (trigger Copilot Studio / Power Automate) | 🔲 TODO | | 1 |
| 4.9 | Copilot Studio chat widget embedded in Power Apps | 🔲 TODO | | 0.5 |
| 4.10 | UAT with sample data and 2 customer scenarios | 🔲 TODO | | 2 |

**Phase 4 Exit Criteria:** End-to-end flow works from Power Apps — customer fills form, gets scored results dashboard, can talk to Copilot agent.

---

### Phase 5 — Copilot Studio Agent 🔲 Not Started

| # | Task | Status | Owner | Est. Days |
|---|---|---|---|---|
| 5.1 | Create agent in Copilot Studio, connect Dataverse knowledge | 🔲 TODO | | 0.5 |
| 5.2 | Topic: Get Assessment Summary | 🔲 TODO | | 1 |
| 5.3 | Topic: Generate Migration Wave Plan | 🔲 TODO | | 1.5 |
| 5.4 | Topic: Explain Migration Path | 🔲 TODO | | 1 |
| 5.5 | Topic: Blocker Resolution Help | 🔲 TODO | | 1 |
| 5.6 | Topic: Trigger New Assessment (redirect to Power Apps) | 🔲 TODO | | 0.5 |
| 5.7 | Topic: Export Report (calls Power Automate flow) | 🔲 TODO | | 1 |
| 5.8 | Enable Generative Answers with Azure Migration docs as grounding | 🔲 TODO | | 0.5 |
| 5.9 | Publish agent and embed in Power Apps | 🔲 TODO | | 0.5 |
| 5.10 | End-to-end agent conversation test across all topics | 🔲 TODO | | 1 |

**Phase 5 Exit Criteria:** Agent can answer "How ready is customer X to migrate?" and produce a structured wave plan from Dataverse data.

---

### Phase 6 — Hardening & Customer Packaging 🔲 Not Started

| # | Task | Status | Owner | Est. Days |
|---|---|---|---|---|
| 6.1 | Docker security hardening (non-root user, read-only FS, secret scanning) | 🔲 TODO | | 1 |
| 6.2 | API rate limiting and request logging | 🔲 TODO | | 0.5 |
| 6.3 | Customer deployment guide (customer-facing README) | 🔲 TODO | | 1 |
| 6.4 | One-click setup script (`setup.ps1`) — configures .env, starts container, validates | 🔲 TODO | | 1 |
| 6.5 | Power Platform solution export (`.zip`) for easy customer import | 🔲 TODO | | 0.5 |
| 6.6 | Pilot with first customer (end-to-end run) | 🔲 TODO | | 3 |
| 6.7 | Feedback incorporation and bug fixes | 🔲 TODO | | 2 |

---

## 4. Timeline Summary

```
Week 1  (Jul 21–25)   Phase 1 ✅ + Phase 2 🔲
Week 2  (Jul 28–Aug 1) Phase 3 + Phase 4 (screens 1–4)
Week 3  (Aug 4–8)     Phase 4 (screens 5–10) + Phase 5
Week 4  (Aug 11–15)   Phase 6 + Pilot
```

---

## 5. Key Decisions Log

| # | Decision | Rationale |
|---|---|---|
| D1 | Docker container (not Azure-hosted API) | Must run in customer network to reach on-prem DBs for factory scripts |
| D2 | FastAPI (Python) for REST layer | Lightweight, async, auto-generates OpenAPI spec for custom connector |
| D3 | Dataverse as shared store | Native to Power Platform — no extra infrastructure for Power Apps or Copilot Studio |
| D4 | MSAL client credentials for Dataverse auth | Service principal is the only non-interactive auth method suitable for a daemon container |
| D5 | Factory scripts kept as-is | Avoids drift from upstream `Azure/cloud-accelerate-factory`; orchestrator wraps them |
| D6 | Power Automate as middleware | Decouples Power Apps from Docker; handles async polling without blocking the UI |

---

## 6. Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Customer firewall blocks Docker→Power Platform connectivity | Medium | High | Use Azure Relay or ngrok as fallback tunnel; document both options |
| Oracle info-gather requires SQL*Plus which needs Oracle client install | High | Medium | Document Oracle Instant Client as prerequisite; offer manual gather path |
| Power Apps Custom Connector CORS issues with localhost | Medium | High | Phase 2.7 — evaluate Azure Relay or expose via internal DNS |
| Dataverse API limits (429 throttling) on bulk push | Low | Medium | Add retry logic with exponential backoff in `push_db_items_to_dataverse` |
| Copilot Studio generative answers hallucinate migration facts | Medium | High | Ground all migration topics on `migration-paths.json`; disable open-web search |

---

## 7. Repo Structure

```
DBMigrationAssist/
├── api/                        FastAPI REST API
│   ├── main.py                 All endpoints, Dataverse push, job runner
│   └── requirements.txt
├── assessment-engine/
│   └── data/
│       ├── migration-paths.json
│       ├── questionnaire.json
│       └── scoring-matrix.json
├── connectors/
│   └── openapi.json            Power Apps Custom Connector spec
├── copilot-studio/
│   └── agent-config.json       Topics, flows, knowledge sources
├── dataverse/
│   └── tables.json             Dataverse table schema definitions
├── docker/
│   ├── Dockerfile
│   ├── docker-compose.yml
│   └── .env.example
├── docs/                       ← You are here
│   ├── project-plan.md
│   └── project-plan.html
├── factory-scripts/            Azure Cloud Accelerate Factory scripts
│   ├── PostgreSQL/
│   ├── MySQL/
│   ├── MariaDB/
│   ├── Mongo/
│   ├── Cassandra/
│   ├── Heterogeneous/          Oracle + MSSQL pre-migration cleanup
│   └── SQL/
├── input/
│   └── sample-db-inventory.csv
├── power-apps/                 Power Apps solution files (Phase 4)
├── Invoke-Assessment.ps1       Core scoring orchestrator
└── .github/                    PR template, issue templates, workflows
```

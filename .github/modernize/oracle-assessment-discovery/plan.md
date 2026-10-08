# Implementation Plan: Oracle Target Assessment and Dependency Discovery

**Date**: 2026-10-06 | **Spec**: `spec.md`

## Summary

Extend the current Oracle collector into a governed assessment system that reconciles machine, uploaded and questionnaire evidence; evaluates migration targets in the required order using deterministic versioned rules; discovers dependency candidates; promotes reviewed candidates into the authoritative communication map; and generates dependency-aware portfolio and migration-wave suggestions. Existing agent submissions, manual edges, portfolios and approved reports remain available throughout the phased rollout.

## Technical Context

**Language/Version**: C# on .NET 8; TypeScript 6 with React 19
**Primary Dependencies**: ASP.NET Core, EF Core 8, Npgsql, Oracle Managed Data Access, React Query, Axios, React Flow
**Storage**: PostgreSQL with existing `core`, `inventory`, `assessment`, `questionnaire`, `graph`, `reporting` and `audit` schemas; filesystem evidence content
**Testing**: xUnit with SQLite/PostgreSQL integration coverage, Vitest component tests, Docker Compose runtime validation, representative Oracle certification fixtures and live-version runs
**Target Platform**: Existing local Docker and Azure-hosted deployment modes
**Performance Goals**: Idempotent evidence processing and discovery; no duplicate candidates; project assessment and graph reads remain interactive for the existing estate scale
**Constraints**: Outbound-only agent; HMAC agent contract compatibility; CSRF-protected portal mutations; preserve existing manual data; no AI-only decisions; database-scoped questionnaire evidence for database decisions

## Constitution Check

No project `constitution.md` exists. The plan therefore applies the repository engineering constraints and the accepted feature specification:

- **Pass — Evidence preservation**: Original findings, uploads, answers and decisions are immutable inputs to versioned snapshots.
- **Pass — Explicit errors**: Unsupported contracts, missing mandatory evidence and invalid transitions fail explicitly.
- **Pass — Compatibility**: Existing agent, graph and portfolio contracts remain during migration.
- **Pass — Authorization**: Project scope and owner-only approvals are enforced at object level.
- **Pass — Determinism**: Target gates and progression are rule-driven; AI provides narrative only.
- **Pass — Traceability**: Every recommendation records rule-set and evidence versions.

## Applied Guidelines

No repository migration guideline matches this additive .NET/React feature. The plan applies existing repository patterns: EF Core migrations, controller/service separation, versioned questionnaire JSON, React Query server state, antiforgery on mutations, and focused xUnit/Vitest validation.

## Implementation Steps

### Step 1: Versioned evidence and assessment foundation

#### Plan 1.1 — Persist versioned evidence and target decisions
- **Requirements**: REQ-001, REQ-002, REQ-003, REQ-005, REQ-017, REQ-019, REQ-021, REQ-036, REQ-040
- **Design inputs**: `architecture/data-model.md`, `architecture/migration_boundary.yaml`
- **Description**: Add normalized evidence items, conflicts, baselines, rule sets, target assessments, gate outcomes and target decisions while retaining original result JSON and evidence bundles.

#### Plan 1.2 — Parse and reconcile Oracle evidence
- **Requirements**: REQ-001, REQ-002, REQ-003, REQ-005, REQ-006
- **Design inputs**: `architecture/units/oracle-collector/behavior.yaml`, `architecture/seams.yaml`
- **Description**: Select parsers by collection-contract version, normalize collector and uploaded evidence, verify identity/scope and create explicit gaps or conflicts.

#### Plan 1.3 — Enforce completeness and approval readiness
- **Requirements**: REQ-004, REQ-006, REQ-010, REQ-039
- **Design inputs**: `spec.md`, `architecture/cross_unit_state.yaml`
- **Description**: Compute mandatory evidence state by gate and expose blocking evidence, conflicts and scope mismatches.

### Step 2: Questionnaire evidence

#### Plan 2.1 — Publish Oracle questionnaire v4
- **Requirements**: REQ-007, REQ-008, REQ-010
- **Design inputs**: Existing `oracle-v3.json`, `research.md`
- **Description**: Add explicit database-scoped questions and attachments for vendor certification, active/licensed features, application remediation, RTO/RPO, downtime, rollback, security, operations, economics and accountable approvals.

#### Plan 2.2 — Attribute and reconcile questionnaire evidence
- **Requirements**: REQ-002, REQ-005, REQ-008, REQ-009, REQ-010
- **Design inputs**: `architecture/units/questionnaire-api/behavior.yaml`
- **Description**: Map answers to evidence categories and target gates, retain respondent and attachment provenance, and create conflicts when observed and declared facts disagree.

### Step 3: PostgreSQL-first target assessment

#### Plan 3.1 — Define the versioned assessment rule contract
- **Requirements**: REQ-011, REQ-012, REQ-017, REQ-020, REQ-021
- **Design inputs**: `research.md`, official standards and product capability sources recorded with the rule set
- **Description**: Define deterministic rule inputs, applicability, evidence requirements, severity, outcome, remediation, effort and validation action.

#### Plan 3.2 — Implement PostgreSQL gate evaluation
- **Requirements**: REQ-011, REQ-012, REQ-017, REQ-020
- **Design inputs**: Oracle collector sections, questionnaire evidence categories
- **Description**: Evaluate vendor, feature, schema/code, application, integration, data movement, performance, availability, recovery, security, operations, economics and proof-of-concept gates.

### Step 4: Microsoft SQL fallback assessment

#### Plan 4.1 — Implement Azure SQL Managed Instance evaluation
- **Requirements**: REQ-013, REQ-017, REQ-018, REQ-020
- **Design inputs**: PostgreSQL decision, shared rule contract
- **Description**: Run only after a governed PostgreSQL rejection or deferral and preserve the higher-preference decision.

#### Plan 4.2 — Implement SQL Server on Azure VM evaluation
- **Requirements**: REQ-014, REQ-017, REQ-018, REQ-019, REQ-020
- **Design inputs**: Managed Instance outcome, operating-model evidence
- **Description**: Evaluate SQL VM separately when SQL compatibility remains viable but managed-service gates fail.

### Step 5: Oracle-on-Azure final fallback

#### Plan 5.1 — Implement Oracle Database@Azure evaluation
- **Requirements**: REQ-015, REQ-017, REQ-018, REQ-019, REQ-020
- **Design inputs**: Modernization decisions, Oracle topology/licensing/recovery evidence
- **Description**: Evaluate service eligibility, topology, region, performance, networking, security, availability, recovery, licensing and operating ownership.

#### Plan 5.2 — Implement Oracle on Azure VM evaluation
- **Requirements**: REQ-016, REQ-017, REQ-018, REQ-019, REQ-020
- **Design inputs**: Oracle Database@Azure outcome, Oracle MAA and Azure infrastructure requirements
- **Description**: Evaluate the self-managed final fallback and mark strategic versus interim recommendations.

#### Plan 5.3 — Orchestrate ordered progression
- **Requirements**: REQ-011, REQ-013, REQ-014, REQ-015, REQ-016, REQ-018, REQ-019, REQ-021
- **Design inputs**: All target evaluators
- **Description**: Enforce target order, explicit advancement decisions and historical outcome preservation.

### Step 6: Dependency candidate discovery

#### Plan 6.1 — Persist discovery candidates and unresolved endpoints
- **Requirements**: REQ-022, REQ-023, REQ-024, REQ-025, REQ-026
- **Design inputs**: `architecture/data-model.md`, current graph entities
- **Description**: Add candidate, observation, evidence-reference, endpoint-resolution and status history records with deduplication keys and staleness state.

#### Plan 6.2 — Extract Oracle dependency observations
- **Requirements**: REQ-022, REQ-023, REQ-024, REQ-025
- **Design inputs**: database links, remote synonyms, services, scheduler jobs, refresh groups, uploaded registers and questionnaire evidence
- **Description**: Normalize direct, inferred and asserted observations without inventing inventory matches.

#### Plan 6.3 — Refresh candidates idempotently
- **Requirements**: REQ-024, REQ-025, REQ-026
- **Design inputs**: Versioned evidence baseline and candidate persistence
- **Description**: Merge equivalent observations, preserve all provenance, refresh last-seen timestamps and mark stale candidates without deletion.

### Step 7: Candidate review and authoritative communication map

#### Plan 7.1 — Add governed review transitions
- **Requirements**: REQ-027, REQ-028, REQ-029, REQ-030, REQ-031, REQ-036, REQ-037
- **Design inputs**: `architecture/seams.yaml`, existing graph compatibility contract
- **Description**: Implement accept, reject, merge, correct, resolve and re-review transitions with project authorization and rationale requirements.

#### Plan 7.2 — Migrate existing manual edges safely
- **Requirements**: REQ-029, REQ-031, REQ-040
- **Design inputs**: Existing `GraphEdge` rows and legacy batch-save contract
- **Description**: Backfill manual edges as asserted, reviewed candidates linked to unchanged authoritative edges.

#### Plan 7.3 — Build the candidate-review portal
- **Requirements**: REQ-027, REQ-028, REQ-029, REQ-030, REQ-031
- **Design inputs**: `architecture/units/communication-map-page/*`
- **Description**: Add candidate queue, evidence/provenance details, endpoint resolution, review actions and re-review indicators alongside the current map.

### Step 8: Dependency-aware portfolios and waves

#### Plan 8.1 — Generate explainable portfolio and wave suggestions
- **Requirements**: REQ-032, REQ-033, REQ-034
- **Design inputs**: Accepted graph, target decisions, inventory and questionnaire constraints
- **Description**: Generate deterministic suggestions that explain connectivity, strongly connected groups, external endpoints, target affinity, blockers and ordering.

#### Plan 8.2 — Govern suggestion acceptance and staleness
- **Requirements**: REQ-034, REQ-035, REQ-036, REQ-037, REQ-040
- **Design inputs**: Existing portfolio compatibility contract
- **Description**: Preserve accepted planner-owned records, rule/evidence versions and stale-review state.

#### Plan 8.3 — Migrate manual portfolios and update the portal
- **Requirements**: REQ-034, REQ-035, REQ-040
- **Design inputs**: `architecture/units/portfolio-page/*`
- **Description**: Backfill existing portfolios as accepted manual groupings and add suggestion comparison, acceptance and stale-state experiences.

### Step 9: Reporting, approval and reassessment

#### Plan 9.1 — Expose assessment and discovery APIs
- **Requirements**: REQ-003, REQ-004, REQ-017, REQ-018, REQ-021, REQ-023, REQ-027, REQ-032, REQ-037
- **Design inputs**: Existing authentication and project access patterns
- **Description**: Add project/database-scoped endpoints for evidence, assessment runs, target decisions, candidates, review history, suggestions and approvals.

#### Plan 9.2 — Add the Oracle assessment portal
- **Requirements**: REQ-003, REQ-004, REQ-010, REQ-017, REQ-018, REQ-019, REQ-020, REQ-021, REQ-037, REQ-039
- **Design inputs**: Existing portal layout, report and questionnaire patterns
- **Description**: Add evidence completeness, ordered target comparison, gate detail, progression decisions, validation actions and approval blocking.

#### Plan 9.3 — Extend evidence bundles and reports
- **Requirements**: REQ-019, REQ-021, REQ-038, REQ-039, REQ-040
- **Design inputs**: `architecture/units/report-generation-api/*`
- **Description**: Include deterministic assessment, discovery, unresolved candidates, wave suggestions, exceptions and versions in immutable bundles and generated reports.

### Step 10: Compatibility, certification and documentation

#### Plan 10.1 — Validate deterministic rules and lifecycle invariants
- **Requirements**: REQ-003, REQ-004, REQ-017, REQ-018, REQ-021, REQ-024, REQ-026, REQ-027, REQ-030, REQ-035, REQ-039, REQ-040
- **Design inputs**: All service and persistence contracts
- **Description**: Add focused tests for rule outcomes, order enforcement, evidence conflicts, idempotency, transitions, stale state and historical preservation.

#### Plan 10.2 — Certify representative Oracle topologies and evidence modes
- **Requirements**: REQ-001, REQ-006, REQ-011, REQ-012, REQ-022
- **Design inputs**: Current Oracle collector and certification fixtures
- **Description**: Validate non-CDB, CDB/PDB, single-instance, RAC, restricted permissions, connected/offline results and representative AWR periods.

#### Plan 10.3 — Update current-system documentation and operations
- **Requirements**: REQ-021, REQ-036, REQ-038, REQ-040
- **Design inputs**: Current documentation baseline
- **Description**: Document supported targets, evidence rules, discovery lifecycle, reassessment, certification scope, deployment migration and rollback.

## Project Structure

```text
src/
├── agent/AssessmentToolkit.Agent/Plugins/
│   └── OraclePlugin.cs
├── backend/
│   ├── AssessmentToolkit.Core/Entities/
│   │   ├── OracleAssessmentEntities.cs
│   │   └── DiscoveryEntities.cs
│   ├── AssessmentToolkit.Data/
│   │   ├── AssessmentDbContext.cs
│   │   └── Migrations/
│   └── AssessmentToolkit.Api/
│       ├── Controllers/
│       │   ├── OracleAssessmentsController.cs
│       │   ├── DependencyDiscoveryController.cs
│       │   ├── GraphController.cs
│       │   └── PortfolioController.cs
│       ├── Services/
│       │   ├── OracleEvidence/
│       │   ├── OracleAssessment/
│       │   └── Discovery/
│       └── QuestionnaireTemplates/oracle-v4.json
├── frontend/src/
│   ├── pages/OracleAssessments.tsx
│   ├── pages/CommunicationMap.tsx
│   ├── pages/Portfolio.tsx
│   └── lib/api.ts
└── tests/AssessmentToolkit.Api.Tests/
    ├── OracleEvidenceBaselineTests.cs
    ├── OracleTargetAssessmentTests.cs
    ├── DependencyDiscoveryTests.cs
    └── PortfolioSuggestionTests.cs
```

## Testing Strategy

- **appType**: Mixed SPA, REST API, background services and outbound database agent.
- **Critical user journeys**:
  1. Collect and reconcile a complete Oracle evidence baseline.
  2. Evaluate targets in the mandated order and approve a recommendation.
  3. Discover, review and accept a dependency candidate.
  4. Generate, review and accept a dependency-aware portfolio or wave.
  5. Reassess with new evidence without changing historical decisions.
- **primaryValidationStack**: xUnit service/controller tests with PostgreSQL-compatible integration coverage; Vitest portal tests; Docker Compose smoke validation; representative live Oracle certification.
- **fallbackMatrix**:
  - `infra-tier`: Docker Compose PostgreSQL and Oracle lab → SQLite for deterministic service tests. Prerequisite: Docker and licensed/approved Oracle test environment.
  - `browser-tier`: Browser-level portal journey tests → Vitest component tests. Prerequisite: Node.js and browser tooling.
- **Environment requirements**: .NET 8 SDK, Node.js compatible with Vite 8, Docker, PostgreSQL, and representative Oracle environments/fixtures.
- **knownGaps**: SQLite cannot validate PostgreSQL indexes/JSON behavior; fixtures cannot certify Oracle privileges/version behavior; component tests cannot validate full cookie/CSRF navigation.
- **Test data strategy**: Versioned sanitized Oracle finding fixtures, database-scoped questionnaire fixtures, deterministic dependency aliases, isolated project/database IDs and cleanup after integration runs.
- **Acceptance criteria**: All target-order, evidence-blocking, deduplication, review, staleness, historical-preservation and compatibility scenarios pass; representative Oracle certification results are recorded by version/topology.
- **Validation review expectations**: Confirm existing agent submissions, manual edges, portfolios and reports remain usable; no recommendation bypasses required evidence or target order.

## Task Breakdown

### Phase 1 — Setup and foundational persistence

- [ ] T001 [Plan:1.1] Add evidence baseline, evidence item, conflict, rule set, target assessment, gate outcome and target decision entities in `src/backend/AssessmentToolkit.Core/Entities/OracleAssessmentEntities.cs`
- [ ] T002 [P] [Plan:6.1] Add dependency candidate, observation, endpoint resolution, review history and status entities in `src/backend/AssessmentToolkit.Core/Entities/DiscoveryEntities.cs`
- [ ] T003 [P] [Plan:8.2] Add portfolio suggestion, membership rationale and review-state entities in `src/backend/AssessmentToolkit.Core/Entities/DiscoveryEntities.cs`
- [ ] T004 [Plan:1.1,6.1,8.2] Map new entities, relationships, indexes and JSON fields in `src/backend/AssessmentToolkit.Data/AssessmentDbContext.cs`
- [ ] T005 [Plan:1.1,6.1,8.2] Generate and review the additive EF Core migration under `src/backend/AssessmentToolkit.Data/Migrations/`
- [ ] T006 [Plan:7.2,8.3] Add idempotent backfill logic for existing `GraphEdge` and `Portfolio` rows in the new migration

### Phase 2 — Evidence baseline and questionnaire

- [ ] T007 [US1] [Plan:1.2] Implement version-selected collector parsing in `src/backend/AssessmentToolkit.Api/Services/OracleEvidence/OracleCollectorEvidenceParser.cs` [Source: src/agent/AssessmentToolkit.Agent/Plugins/OraclePlugin.cs#RunAsync]
- [ ] T008 [P] [US1] [Plan:1.2] Implement database identity and scope reconciliation in `src/backend/AssessmentToolkit.Api/Services/OracleEvidence/OracleEvidenceIdentityService.cs`
- [ ] T009 [P] [US1] [Plan:1.2] Implement uploaded and workload evidence normalization in `src/backend/AssessmentToolkit.Api/Services/OracleEvidence/OracleUploadedEvidenceAdapter.cs`
- [ ] T010 [US1] [Plan:1.2,2.2] Implement provenance-preserving evidence reconciliation and conflict creation in `src/backend/AssessmentToolkit.Api/Services/OracleEvidence/OracleEvidenceBaselineService.cs`
- [ ] T011 [US1] [Plan:1.3] Implement gate-aware completeness evaluation in `src/backend/AssessmentToolkit.Api/Services/OracleEvidence/OracleEvidenceCompletenessService.cs`
- [ ] T012 [P] [US1] [Plan:2.1] Add versioned target, licensing, vendor, recovery, security, cost and approval questions in `src/backend/AssessmentToolkit.Api/QuestionnaireTemplates/oracle-v4.json`
- [ ] T013 [US1] [Plan:2.2] Map database-scoped Oracle answers and attachments into evidence categories in `src/backend/AssessmentToolkit.Api/Services/OracleEvidence/OracleQuestionnaireEvidenceAdapter.cs`
- [ ] T014 [US1] [Plan:2.2] Extend `src/backend/AssessmentToolkit.Api/Controllers/QuestionnairesController.cs` responses with blocking evidence references while preserving existing drafts
- [ ] T015 [US1] [Plan:1.2] Invoke baseline refresh after validated Oracle result submission in `src/backend/AssessmentToolkit.Api/Controllers/AgentJobsController.cs`

### Phase 3 — Ordered target assessment

- [ ] T016 [US2] [Plan:3.1] Define versioned rule, gate, outcome, remediation and effort contracts in `src/backend/AssessmentToolkit.Api/Services/OracleAssessment/AssessmentRuleContracts.cs`
- [ ] T017 [US2] [Plan:3.1] Create the initial standards-source manifest and rule set in `src/backend/AssessmentToolkit.Api/AssessmentRules/oracle-targets-v1.json`
- [ ] T018 [US2] [Plan:3.2] Implement PostgreSQL Flexible Server evaluator in `src/backend/AssessmentToolkit.Api/Services/OracleAssessment/PostgreSqlTargetEvaluator.cs`
- [ ] T019 [P] [US2] [Plan:4.1] Implement Azure SQL Managed Instance evaluator in `src/backend/AssessmentToolkit.Api/Services/OracleAssessment/SqlManagedInstanceTargetEvaluator.cs`
- [ ] T020 [P] [US2] [Plan:4.2] Implement SQL Server on Azure VM evaluator in `src/backend/AssessmentToolkit.Api/Services/OracleAssessment/SqlServerVmTargetEvaluator.cs`
- [ ] T021 [P] [US2] [Plan:5.1] Implement Oracle Database@Azure evaluator in `src/backend/AssessmentToolkit.Api/Services/OracleAssessment/OracleDatabaseAtAzureTargetEvaluator.cs`
- [ ] T022 [P] [US2] [Plan:5.2] Implement Oracle on Azure VM evaluator in `src/backend/AssessmentToolkit.Api/Services/OracleAssessment/OracleAzureVmTargetEvaluator.cs`
- [ ] T023 [US2] [Plan:5.3] Implement ordered progression, advancement decisions and strategic/interim recommendation selection in `src/backend/AssessmentToolkit.Api/Services/OracleAssessment/OracleAssessmentOrchestrator.cs`
- [ ] T024 [US2] [Plan:1.3,5.3] Enforce evidence readiness and governed exceptions in `src/backend/AssessmentToolkit.Api/Services/OracleAssessment/OracleAssessmentApprovalService.cs`

### Phase 4 — Dependency discovery

- [ ] T025 [US3] [Plan:6.2] Implement Oracle link, remote-synonym, service, scheduler and refresh observation extraction in `src/backend/AssessmentToolkit.Api/Services/Discovery/OracleDependencyExtractor.cs`
- [ ] T026 [P] [US3] [Plan:6.2] Implement questionnaire and uploaded-register observation extraction in `src/backend/AssessmentToolkit.Api/Services/Discovery/DeclaredDependencyExtractor.cs`
- [ ] T027 [US3] [Plan:6.3] Implement endpoint normalization, inventory matching and unresolved endpoint handling in `src/backend/AssessmentToolkit.Api/Services/Discovery/DependencyEndpointResolver.cs`
- [ ] T028 [US3] [Plan:6.3] Implement idempotent candidate reconciliation, provenance merge and staleness refresh in `src/backend/AssessmentToolkit.Api/Services/Discovery/DependencyCandidateService.cs`
- [ ] T029 [US3] [Plan:6.2,6.3] Trigger deterministic dependency discovery after baseline refresh in `src/backend/AssessmentToolkit.Api/Services/OracleEvidence/OracleEvidenceBaselineService.cs`

### Phase 5 — Candidate review and communication map

- [ ] T030 [US4] [Plan:7.1] Implement authorized candidate accept, reject, merge, correct, resolve and re-review transitions in `src/backend/AssessmentToolkit.Api/Services/Discovery/DependencyReviewService.cs`
- [ ] T031 [US4] [Plan:9.1] Add project-scoped candidate query and review routes in `src/backend/AssessmentToolkit.Api/Controllers/DependencyDiscoveryController.cs`
- [ ] T032 [US4] [Plan:7.1,7.2] Extend `src/backend/AssessmentToolkit.Api/Controllers/GraphController.cs` to expose evidence-linked authoritative edges without changing legacy batch-save behavior
- [ ] T033 [US4] [Plan:7.3,9.1] Add typed candidate and review API functions in `src/frontend/src/lib/api.ts`
- [ ] T034 [US4] [Plan:7.3] Add candidate queue, provenance, endpoint resolution and review actions to `src/frontend/src/pages/CommunicationMap.tsx`
- [ ] T035 [US4] [Plan:7.3] Add accepted-edge evidence and re-review indicators to `src/frontend/src/pages/CommunicationMap.tsx`

### Phase 6 — Portfolio and wave suggestions

- [ ] T036 [US5] [Plan:8.1] Implement graph component, strongly connected group and sequencing analysis in `src/backend/AssessmentToolkit.Api/Services/Discovery/PortfolioSuggestionService.cs`
- [ ] T037 [US5] [Plan:8.1] Add target affinity, ownership, criticality, downtime and blocker rationale to `src/backend/AssessmentToolkit.Api/Services/Discovery/PortfolioSuggestionService.cs`
- [ ] T038 [US5] [Plan:8.2] Implement suggestion acceptance, staleness and reassessment transitions in `src/backend/AssessmentToolkit.Api/Services/Discovery/PortfolioReviewService.cs`
- [ ] T039 [US5] [Plan:8.2,9.1] Add suggestion, acceptance and history routes to `src/backend/AssessmentToolkit.Api/Controllers/PortfolioController.cs`
- [ ] T040 [US5] [Plan:8.3] Add typed suggestion and review API functions in `src/frontend/src/lib/api.ts`
- [ ] T041 [US5] [Plan:8.3] Add generated suggestion comparison, acceptance rationale and stale-state UI to `src/frontend/src/pages/Portfolio.tsx`

### Phase 7 — Assessment portal, reporting and approval

- [ ] T042 [US6] [Plan:9.1] Add evidence, run, target decision, advancement, approval and history routes in `src/backend/AssessmentToolkit.Api/Controllers/OracleAssessmentsController.cs`
- [ ] T043 [US6] [Plan:9.2] Add typed Oracle assessment API contracts in `src/frontend/src/lib/api.ts` and `src/frontend/src/types/index.ts`
- [ ] T044 [US6] [Plan:9.2] Implement evidence completeness, conflict and questionnaire-gap views in `src/frontend/src/pages/OracleAssessments.tsx`
- [ ] T045 [US6] [Plan:9.2] Implement ordered target comparison, gate details, progression and validation actions in `src/frontend/src/pages/OracleAssessments.tsx`
- [ ] T046 [US6] [Plan:9.2] Implement owner approval, governed exception and historical assessment views in `src/frontend/src/pages/OracleAssessments.tsx`
- [ ] T047 [US6] [Plan:9.2] Register the `/oracle-assessments` route and navigation item in `src/frontend/src/App.tsx` and `src/frontend/src/components/Layout.tsx`
- [ ] T048 [US6] [Plan:9.3] Extend immutable evidence-bundle assembly in `src/backend/AssessmentToolkit.Api/Controllers/AiController.cs` with deterministic assessment and discovery snapshots
- [ ] T049 [US6] [Plan:9.3] Extend generated report contracts in `src/backend/AssessmentToolkit.Api/Services/GeneratedReportContract.cs` with ordered targets, blockers, dependencies, waves and approval state
- [ ] T050 [US6] [Plan:9.3] Update `report-config/report-instructions.md` to explain deterministic findings without allowing narrative output to override them

### Phase 8 — Validation and documentation

- [ ] T051 [P] [Plan:10.1] Add evidence identity, provenance, conflict and completeness tests in `src/tests/AssessmentToolkit.Api.Tests/OracleEvidenceBaselineTests.cs`
- [ ] T052 [P] [Plan:10.1] Add target-rule, progression, exception and historical-preservation tests in `src/tests/AssessmentToolkit.Api.Tests/OracleTargetAssessmentTests.cs`
- [ ] T053 [P] [Plan:10.1] Add discovery deduplication, unresolved endpoint, review and staleness tests in `src/tests/AssessmentToolkit.Api.Tests/DependencyDiscoveryTests.cs`
- [ ] T054 [P] [Plan:10.1] Add portfolio component, ordering, acceptance and stale-state tests in `src/tests/AssessmentToolkit.Api.Tests/PortfolioSuggestionTests.cs`
- [ ] T055 [P] [Plan:10.1] Add portal tests for blocked approval, candidate review and stale portfolio states under `src/frontend/src/pages/`
- [ ] T056 [Plan:10.2] Add sanitized Oracle 11g/19c/21c, non-CDB/CDB, single/RAC and restricted-permission fixtures under `src/tests/AssessmentToolkit.Api.Tests/Fixtures/Oracle/`
- [ ] T057 [Plan:10.2] Add a repeatable Oracle live-certification script under `tests/OracleAssessmentE2E.ps1`
- [ ] T058 [Plan:10.1,10.2] Run targeted backend, frontend, migration and Docker Compose validation and record failures against their owning tasks
- [ ] T059 [Plan:10.3] Update `docs/current/SYSTEM_OVERVIEW.md`, `docs/current/ARCHITECTURE_AND_SECURITY.md`, `docs/current/API_REFERENCE.md` and `docs/current/KNOWN_LIMITATIONS.md`
- [ ] T060 [Plan:10.3] Update `docs/current/OPERATIONS_AND_DEPLOYMENT.md` with migration, backfill, reassessment, rollback and Oracle certification procedures

## Requirement Mapping

| REQ ID | Description | Plan Items | Implementation Evidence |
|---|---|---|---|
| REQ-001 | Versioned Oracle evidence baseline | 1.1, 1.2, 10.2 | Evidence entities, parsers, baseline service, certification fixtures |
| REQ-002 | Combine evidence with provenance | 1.1, 1.2, 2.2 | Evidence items and adapters |
| REQ-003 | Evidence state classification | 1.1, 1.2, 9.1, 10.1 | Completeness service and API |
| REQ-004 | Mandatory evidence blocks approval | 1.3, 9.1, 9.2, 10.1 | Approval service and portal |
| REQ-005 | Preserve originals during resolution | 1.1, 1.2, 2.2 | Conflict and evidence records |
| REQ-006 | Verify database identity and scope | 1.2, 1.3, 10.2 | Identity service and fixtures |
| REQ-007 | Complete Oracle questionnaire | 2.1 | `oracle-v4.json` |
| REQ-008 | Attributed database-scoped answers | 2.1, 2.2 | Questionnaire adapter |
| REQ-009 | Reconcile observed and declared facts | 2.2 | Conflict creation |
| REQ-010 | Direct users to blocking questions | 1.3, 2.1, 2.2, 9.2 | Completeness output and portal links |
| REQ-011 | PostgreSQL assessed first | 3.1, 3.2, 5.3, 10.2 | PostgreSQL evaluator and orchestrator |
| REQ-012 | PostgreSQL gate coverage | 3.2, 10.2 | Rules and evaluator |
| REQ-013 | SQL MI follows PostgreSQL decision | 4.1, 5.3 | MI evaluator and progression |
| REQ-014 | SQL VM separate fallback | 4.2, 5.3 | SQL VM evaluator |
| REQ-015 | Database@Azure after modernization | 5.1, 5.3 | Database@Azure evaluator |
| REQ-016 | Oracle VM final fallback | 5.2, 5.3 | Oracle VM evaluator |
| REQ-017 | Independently reviewable gate outcomes | 1.1, 3.1, 3.2, 4.1, 4.2, 5.1, 5.2, 9.1, 9.2, 10.1 | Gate records, evaluators and portal |
| REQ-018 | Governed target advancement | 4.1, 4.2, 5.1, 5.2, 5.3, 9.1, 9.2, 10.1 | Target decisions and transitions |
| REQ-019 | Strategic/interim recommendation | 1.1, 4.2, 5.1, 5.2, 5.3, 9.2, 9.3 | Decision and report contracts |
| REQ-020 | Required validation activities | 3.1, 3.2, 4.1, 4.2, 5.1, 5.2, 9.2 | Rule actions and portal |
| REQ-021 | Rule and evidence version traceability | 1.1, 3.1, 5.3, 9.1, 9.2, 9.3, 10.1, 10.3 | Rule sets, snapshots and docs |
| REQ-022 | Discover from technical and declared evidence | 6.1, 6.2, 10.2 | Extractors and candidates |
| REQ-023 | Candidate provenance fields | 6.1, 6.2, 9.1 | Candidate/observation entities |
| REQ-024 | Deduplicate and classify evidence | 6.1, 6.2, 6.3, 10.1 | Candidate service |
| REQ-025 | Preserve unresolved endpoints | 6.1, 6.2, 6.3 | Endpoint resolver |
| REQ-026 | Refresh without deletion | 6.1, 6.3, 10.1 | Staleness lifecycle |
| REQ-027 | Review before authoritative edge | 7.1, 7.3, 9.1, 10.1 | Review service, API and UI |
| REQ-028 | Full review actions with rationale | 7.1, 7.3 | Review transitions |
| REQ-029 | Accepted edge evidence/history | 7.1, 7.2, 7.3 | Edge/candidate linkage |
| REQ-030 | Re-review on material change | 7.1, 7.3, 10.1 | Re-review state |
| REQ-031 | Manual assertions share lifecycle | 7.1, 7.2, 7.3 | Backfill and asserted candidates |
| REQ-032 | Generate portfolio/wave suggestions | 8.1, 9.1 | Suggestion service and API |
| REQ-033 | Explain coupling and ordering | 8.1 | Graph-analysis rationale |
| REQ-034 | Review suggestions before acceptance | 8.1, 8.2, 8.3 | Suggestion review |
| REQ-035 | Mark accepted groups stale | 8.2, 8.3, 10.1 | Portfolio review service |
| REQ-036 | Auditable governed actions | 1.1, 7.1, 8.2, 10.3 | History records and governance audit |
| REQ-037 | Role-based approvals | 7.1, 8.2, 9.1, 9.2 | Project access checks |
| REQ-038 | Complete assessment reports | 9.3, 10.3 | Bundle and report contracts |
| REQ-039 | Block unsafe approval or govern exception | 1.3, 9.2, 9.3, 10.1 | Approval service and report state |
| REQ-040 | Reassessment preserves history | 1.1, 7.2, 8.2, 8.3, 9.3, 10.1, 10.3 | Versioned records and operations docs |

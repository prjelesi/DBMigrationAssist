# Feature Specification: Oracle Target Assessment and Dependency Discovery

**Created**: 2026-10-06
**Status**: Draft
**Input**: Assess Oracle databases in a strict target order—Azure Database for PostgreSQL Flexible Server, Azure SQL Managed Instance with SQL Server on Azure Virtual Machines as fallback, Oracle Database@Azure with Oracle Database on Azure Virtual Machines as final fallback—and replace manually maintained communication maps and portfolios with evidence-backed discovery and governed review. Questionnaire responses are valid assessment evidence for facts that cannot be collected safely from the database.

## Scope Baseline

- **Discovery method**: Reviewed the current Oracle collector contract, Oracle questionnaire, report evidence summarization, graph-edge workflow, portfolio workflow, current system documentation, and the sample migration decision framework.
- **Total items discovered**: 65 Oracle collector sections, 1 Oracle questionnaire template, 1 report evidence summarizer, 1 manual graph workflow, and 1 manual portfolio workflow.
- **Items in scope**: All Oracle assessment, questionnaire, dependency-discovery, target-decision, communication-map, and portfolio behaviors needed for the ordered migration decision.
- **Out of scope**: Executing production migrations, automatically modifying source databases or applications, producing binding Oracle license advice, and approving a migration without accountable human review.

## User Scenarios & Testing

### User Story 1 - Build a complete Oracle evidence baseline (Priority: P1)

As a migration assessor, I want each Oracle database to have a consolidated and quality-checked evidence baseline so that target recommendations are based on current technical facts, workload evidence, and accountable stakeholder input.

**Why this priority**: Every target assessment and discovered dependency depends on trustworthy source evidence.

**Independent Test**: Assess a representative Oracle database, upload workload evidence, complete its Oracle questionnaire, and verify that collected, uploaded, and questionnaire evidence are reconciled into a completeness result with explicit gaps and conflicts.

**Acceptance Scenarios**:

1. **Given** a registered Oracle database and a successful connected assessment, **When** the evidence baseline is viewed, **Then** it identifies the collector contract, database identity, topology, capacity, workload, compatibility features, collection time, and unavailable sections.
2. **Given** a fact that cannot be determined safely from database views, **When** an authorized stakeholder answers the database-scoped Oracle questionnaire and attaches supporting material, **Then** the answer appears as attributed evidence with its source and review status.
3. **Given** collected evidence and a questionnaire answer that disagree, **When** the baseline is evaluated, **Then** neither value silently wins and an evidence conflict requiring review is shown.
4. **Given** missing evidence required for a target decision, **When** an assessor attempts to finalize the assessment, **Then** the system identifies the blocking gap and the evidence needed to resolve it.

---

### User Story 2 - Evaluate targets in a governed order (Priority: P1)

As a migration architect, I want every Oracle database evaluated against a consistent target hierarchy so that modernization is preferred and fallback decisions are evidence-based.

**Why this priority**: The ordered target decision is the primary business outcome of the feature.

**Independent Test**: Run the assessment for one database containing representative Oracle features and verify that each target receives gate outcomes, evidence, remediation, effort, and a decision before the next branch is selected.

**Acceptance Scenarios**:

1. **Given** a complete evidence baseline, **When** target assessment runs, **Then** PostgreSQL Flexible Server is evaluated first.
2. **Given** PostgreSQL has an unresolved hard gate or an approved disproportionate remediation finding, **When** the assessor advances the decision, **Then** Azure SQL Managed Instance is evaluated and the PostgreSQL rejection reason remains visible.
3. **Given** Azure SQL Managed Instance fails a service capability gate but SQL Server remains viable, **When** the SQL fallback is evaluated, **Then** SQL Server on Azure Virtual Machines receives a separate decision and operating-model assessment.
4. **Given** both modernization branches are rejected with evidence, **When** the Oracle branch is evaluated, **Then** Oracle Database@Azure is assessed before Oracle Database on Azure Virtual Machines.
5. **Given** a target is recommended, **When** the decision is reviewed, **Then** alternatives, failed gates, remediation estimates, assumptions, confidence, evidence age, and required proof-of-concept activities are visible.

---

### User Story 3 - Discover dependency candidates (Priority: P1)

As a migration architect, I want database communications and dependencies discovered from assessment evidence so that the communication map does not depend on manual recollection.

**Why this priority**: Missing dependencies are a major source of failed sequencing, cutover, and rollback decisions.

**Independent Test**: Assess an Oracle database with known database links, remote synonyms, services, jobs, and questionnaire-declared integrations and verify that normalized, deduplicated dependency candidates are created with evidence and confidence.

**Acceptance Scenarios**:

1. **Given** a collector result containing a database link or remote synonym, **When** discovery runs, **Then** it creates or refreshes a candidate describing the source, observed destination, dependency type, evidence source, observation time, and confidence.
2. **Given** a questionnaire or uploaded register describing an integration, **When** discovery runs, **Then** it creates an attributed candidate without presenting the stakeholder assertion as directly observed traffic.
3. **Given** multiple evidence sources for the same dependency, **When** candidates are reconciled, **Then** one candidate retains all evidence references and the strongest support rather than creating duplicate edges.
4. **Given** a destination that cannot be matched to inventory, **When** discovery runs, **Then** the unresolved endpoint remains reviewable and is not silently discarded or mapped to an arbitrary database.
5. **Given** a previously observed dependency that is absent from a later collection, **When** discovery refreshes, **Then** the candidate records the latest observation and becomes stale according to policy rather than being silently deleted.

---

### User Story 4 - Review and govern discovered communications (Priority: P2)

As a project contributor or owner, I want to accept, reject, merge, or correct dependency candidates so that the authoritative communication map is evidence-backed and governed.

**Why this priority**: Discovery can be incomplete or ambiguous and must not automatically become authoritative architecture.

**Independent Test**: Review candidate dependencies for a project, accept one, reject one with rationale, and resolve one unknown endpoint; verify the authoritative graph and audit history.

**Acceptance Scenarios**:

1. **Given** an unreviewed candidate, **When** a permitted reviewer accepts it, **Then** an authoritative edge is created or updated and remains linked to its discovery evidence.
2. **Given** a false or irrelevant candidate, **When** a reviewer rejects it, **Then** a reason is required and the same unchanged evidence does not repeatedly recreate an unreviewed duplicate.
3. **Given** an unresolved endpoint, **When** a reviewer maps it to an inventory database, **Then** the resolution is retained separately from the original observed value.
4. **Given** a previously accepted edge whose supporting evidence materially changes, **When** discovery refreshes, **Then** the edge is flagged for re-review without losing its history.
5. **Given** manual knowledge not represented by collected evidence, **When** a reviewer adds an asserted dependency, **Then** it uses the same evidence, confidence, review, and audit model and is visibly distinguished from observed dependencies.

---

### User Story 5 - Generate dependency-aware portfolios and migration waves (Priority: P2)

As a portfolio planner, I want portfolios and candidate migration waves derived from accepted dependencies and assessment outcomes so that groups remain current as evidence changes.

**Why this priority**: A discovered map provides value only when it informs sequencing and planning.

**Independent Test**: Create accepted dependencies across several databases with different target recommendations and verify that generated portfolio suggestions identify coupling, blockers, target affinity, and sequencing constraints.

**Acceptance Scenarios**:

1. **Given** an accepted communication graph, **When** portfolio discovery runs, **Then** it suggests groups based on connectivity, environment, business ownership, target recommendation, and migration constraints.
2. **Given** a strongly connected set of databases, **When** wave suggestions are generated, **Then** the system identifies the coupling and does not independently schedule members without an explicit warning.
3. **Given** an accepted graph or target decision changes, **When** suggestions refresh, **Then** affected portfolios are marked outdated and regenerated suggestions explain the change.
4. **Given** a planner accepts a suggested portfolio or wave, **When** later evidence changes, **Then** the accepted record is retained and flagged for review rather than silently overwritten.

---

### User Story 6 - Review and approve a traceable recommendation (Priority: P2)

As a project owner or administrator, I want the final recommendation to show how every conclusion was reached so that it can pass architecture, security, operations, and business review.

**Why this priority**: The assessment is advisory until accountable owners approve its evidence and trade-offs.

**Independent Test**: Review a completed target decision and verify traceability from recommendation to gates, findings, evidence, questionnaire answers, conflicts, discovery state, and approvals.

**Acceptance Scenarios**:

1. **Given** a target recommendation, **When** its details are opened, **Then** every gate outcome links to current evidence or an explicitly recorded expert judgement.
2. **Given** blocking conflicts, stale mandatory evidence, or unresolved critical dependencies, **When** approval is attempted, **Then** approval is prevented and the blocking reasons are shown.
3. **Given** all mandatory gates and reviews are complete, **When** an owner or administrator approves the recommendation, **Then** the decision, evidence snapshot, rule-set version, approver, and time are preserved.

### Edge Cases

- An Oracle version or edition does not expose a queried view.
- The assessment account lacks permission for one or more mandatory sections.
- A CDB assessment sees only some PDBs or a RAC assessment sees only one instance.
- Database inventory identity does not match DBID, unique name, host, service, or uploaded AWR evidence.
- Installed options conflict with stakeholder-provided license or usage declarations.
- A dependency points to a host, service name, database link descriptor, IP address, or external system not represented in inventory.
- The same remote endpoint is represented by aliases, scan names, connection descriptors, or public synonyms.
- A database has no fresh workload evidence or only a nonrepresentative period.
- A questionnaire is project-scoped when a database-scoped answer is required.
- A rules update changes the outcome of an already approved assessment.
- A manually asserted edge conflicts with current observed evidence.
- A database is recommended for retirement or replacement rather than any migration target.

## Requirements

### Evidence Baseline

- **REQ-001**: The system MUST create a versioned Oracle evidence baseline for each assessed database and identify the database, collection contract, collection time, source, and confidence of each evidence category.
- **REQ-002**: The baseline MUST combine connected collector results, validated offline results, uploaded evidence, database-scoped questionnaire answers, and approved expert assertions without obscuring their different provenance.
- **REQ-003**: The system MUST classify evidence sections as complete, incomplete, unavailable, stale, conflicting, or not applicable and provide a reason for every state other than complete.
- **REQ-004**: The system MUST define mandatory evidence by assessment gate and MUST prevent final approval when mandatory evidence is missing, stale, or conflicting.
- **REQ-005**: The system MUST retain the original submitted evidence and questionnaire answer when a reviewer resolves a conflict or records an interpretation.
- **REQ-006**: The system MUST verify that collector, workload, uploaded, and questionnaire evidence applies to the selected database and MUST flag identity or scope mismatches.

### Questionnaire Evidence

- **REQ-007**: The Oracle questionnaire MUST capture vendor support, application ownership, conversion scope, licensed and actively used Oracle capabilities, availability and recovery objectives, downtime and rollback limits, security requirements, operating ownership, cost constraints, and decision approvals.
- **REQ-008**: Questionnaire answers used by a target gate MUST be database-scoped, attributable to a respondent, time-stamped, and reviewable with attachments where documentary evidence is required.
- **REQ-009**: Observable technical facts SHOULD be sourced from collection evidence; when a questionnaire provides the same fact, the system MUST reconcile the sources and surface material disagreement.
- **REQ-010**: The system MUST identify unanswered or insufficient questionnaire items that block a target gate and direct the assessor to the relevant question.

### Ordered Target Assessment

- **REQ-011**: The system MUST evaluate Azure Database for PostgreSQL Flexible Server as the primary target for every in-scope Oracle database unless the workload is explicitly classified for retirement or replacement.
- **REQ-012**: The PostgreSQL assessment MUST evaluate vendor support, Oracle feature compatibility, schema and code conversion, application changes, integrations, data movement, performance, availability, recovery, security, operations, cost, and proof-of-concept needs.
- **REQ-013**: The system MUST evaluate Azure SQL Managed Instance only after recording the PostgreSQL gate outcomes and the evidence-backed reason that PostgreSQL is not currently viable or proportionate.
- **REQ-014**: The system MUST evaluate SQL Server on Azure Virtual Machines separately when Azure SQL Managed Instance fails a platform capability or operating constraint but SQL Server compatibility remains viable.
- **REQ-015**: The system MUST evaluate Oracle Database@Azure only after both modernization branches have evidence-backed rejection or deferral decisions.
- **REQ-016**: The system MUST evaluate Oracle Database on Azure Virtual Machines as the final fallback when Oracle Database@Azure is unavailable, unsuitable, or fails an approved requirement.
- **REQ-017**: Each target MUST receive independently reviewable gate outcomes of pass, conditional pass, fail, unknown, or not applicable, with severity, rationale, evidence references, confidence, remediation, effort range, and validation action.
- **REQ-018**: Advancing to a lower-preference target MUST require an explicit decision recording the failed or disproportionate higher-preference gates and an accountable reviewer.
- **REQ-019**: The final recommendation MUST distinguish strategic targets from interim targets and MUST retain all assessed alternatives and rejection reasons.
- **REQ-020**: Assessment outcomes MUST identify required proof-of-concept, conversion, reconciliation, performance, failover, security, cutover, rollback, and operational validation activities.
- **REQ-021**: Every assessment and recommendation MUST record the rule-set version and evidence snapshot used so that later rule or evidence changes do not rewrite historical decisions.

### Dependency Discovery

- **REQ-022**: The system MUST derive dependency candidates from Oracle database links, remote synonyms, database services, scheduler and refresh metadata where relevant, assessment findings, uploaded dependency registers, and database-scoped questionnaire answers.
- **REQ-023**: Each dependency candidate MUST retain source and observed endpoint values, dependency type, direction, protocol when known, first and last observation times, evidence references, discovery method, and confidence.
- **REQ-024**: The system MUST deduplicate equivalent observations while preserving all supporting evidence and MUST distinguish directly observed, inferred, and stakeholder-asserted dependencies.
- **REQ-025**: Unmatched destinations MUST remain as unresolved endpoints available for review; they MUST NOT be silently discarded or arbitrarily assigned to inventory records.
- **REQ-026**: Discovery refresh MUST update observation and staleness state without silently deleting accepted, rejected, or previously observed dependencies.

### Candidate Review and Authoritative Graph

- **REQ-027**: Newly discovered dependencies MUST enter an unreviewed candidate state and MUST NOT become authoritative graph edges until accepted by an authorized project contributor, owner, or administrator.
- **REQ-028**: Reviewers MUST be able to accept, reject, merge, correct, and resolve candidate endpoints, and rejection or material correction MUST require a rationale.
- **REQ-029**: Accepted graph edges MUST retain links to their candidates and evidence, while preserving reviewer, review time, confidence, and subsequent re-review history.
- **REQ-030**: Materially changed or stale evidence supporting an accepted edge MUST flag the edge for re-review without removing it from the authoritative map.
- **REQ-031**: Manually asserted dependencies MUST use the same candidate, evidence, review, confidence, staleness, and audit lifecycle as automatically discovered dependencies.

### Dependency-Aware Portfolios

- **REQ-032**: The system MUST generate portfolio and migration-wave suggestions from accepted dependencies, environment, business ownership, target recommendations, criticality, downtime constraints, and unresolved blockers.
- **REQ-033**: Suggestions MUST identify strongly coupled databases, unresolved external endpoints, cross-wave dependencies, and reasons that members should move together or in a specific order.
- **REQ-034**: Suggested portfolios and waves MUST remain proposals until accepted by an authorized reviewer and MUST identify the evidence and rule-set version that produced them.
- **REQ-035**: Changes to accepted dependencies or target decisions MUST mark affected accepted portfolios and waves for review rather than silently changing their membership.

### Governance and Reporting

- **REQ-036**: Assessment, evidence-resolution, candidate-review, target-advance, recommendation-approval, and portfolio-acceptance actions MUST be attributable and auditable.
- **REQ-037**: Only project owners or administrators MUST be able to approve a final target recommendation; contributors MAY collect evidence and review candidates according to project access.
- **REQ-038**: Reports MUST present evidence completeness, target comparisons in the required order, blocking gates, remediation and effort, discovered dependencies, unresolved candidates, proposed wave, assumptions, and approval state.
- **REQ-039**: The system MUST prevent approval when critical evidence conflicts, mandatory gate evidence is unavailable, or critical dependency candidates remain unresolved unless an owner records an explicit governed exception.
- **REQ-040**: The system MUST support reassessment with newer evidence while retaining prior evidence snapshots, decisions, approvals, and graph review history.

### Key Entities

- **Oracle Evidence Baseline**: Versioned collection of technical, workload, uploaded, questionnaire, and expert evidence for one database.
- **Evidence Item**: A sourced fact or document with database scope, provenance, collection or response time, confidence, and review state.
- **Evidence Conflict**: Competing material facts with reviewer resolution and retained originals.
- **Assessment Rule Set**: Versioned definitions of evidence requirements, target gates, outcomes, and decision ordering.
- **Target Assessment**: Gate outcomes and remediation for one database and one candidate target.
- **Target Decision**: Reviewed advancement, rejection, recommendation, or deferral decision with accountable owner.
- **Dependency Candidate**: Discovered, inferred, or asserted communication awaiting review.
- **Unresolved Endpoint**: Observed destination that is not yet mapped to inventory.
- **Authoritative Edge**: Accepted communication relationship linked to evidence and review history.
- **Portfolio Suggestion**: Evidence-derived database grouping or migration-wave proposal.
- **Approved Portfolio/Wave**: Reviewed grouping retained independently from later regenerated suggestions.

## Assumptions

- PostgreSQL means Azure Database for PostgreSQL Flexible Server.
- The Microsoft SQL branch evaluates Azure SQL Managed Instance first and SQL Server on Azure Virtual Machines only as its fallback.
- The Oracle branch evaluates Oracle Database@Azure first and Oracle Database on Azure Virtual Machines only as its fallback.
- Questionnaire evidence supplements rather than replaces observable collector evidence.
- Oracle licensing conclusions require customer entitlement evidence and qualified review; the application records evidence and risk but does not issue legal licensing advice.
- Discovery initially uses evidence already available to the platform and does not require packet capture, invasive tracing, or source-database configuration changes.
- Candidate review is mandatory before discovered dependencies affect the authoritative communication map.
- Existing manual edges and portfolios require migration into the governed lifecycle without loss of user-entered information.

## Success Criteria

### Measurable Outcomes

- **SC-001**: For a representative supported Oracle database, assessors can see the completeness and provenance of all mandatory evidence categories within two minutes of assessment processing.
- **SC-002**: Every completed recommendation shows outcomes for 100% of mandatory gates for each target evaluated before the selected target.
- **SC-003**: No lower-preference target can be approved without an attributable, evidence-backed decision for each skipped or rejected higher-preference target.
- **SC-004**: At least 95% of database-link and remote-synonym dependencies in the certification dataset produce a candidate with the correct source and observed destination.
- **SC-005**: Repeated processing of unchanged evidence creates no duplicate dependency candidates or authoritative edges.
- **SC-006**: Reviewers can accept, reject, or resolve a dependency candidate in under two minutes while retaining its evidence and audit history.
- **SC-007**: Accepted communication edges retain evidence and reviewer traceability through subsequent discovery refreshes and reassessments.
- **SC-008**: Portfolio suggestions identify every strongly connected database group in the certification dataset and explain the coupling evidence.
- **SC-009**: A recommendation with missing mandatory evidence, unresolved critical conflicts, or unresolved critical dependencies cannot be approved without a recorded owner exception.
- **SC-010**: A qualified reviewer can trace every final target recommendation to its rule-set version, evidence snapshot, gate outcomes, questionnaire evidence, discovery state, and approval record.
- **SC-011**: Existing user-created communication edges and portfolios remain available after adoption of the governed discovery workflow.
- **SC-012**: Representative assessments cover supported non-CDB, CDB/PDB, single-instance, and RAC topologies without losing section-level error reporting.

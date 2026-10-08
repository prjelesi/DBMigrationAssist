# Research Decisions

## Decision: Ordered target hierarchy

- **Chosen**: Azure Database for PostgreSQL Flexible Server; then Azure SQL Managed Instance; then SQL Server on Azure Virtual Machines; then Oracle Database@Azure; then Oracle Database on Azure Virtual Machines.
- **Rationale**: Preserves the user-selected modernization-first policy while making service and VM fallbacks independently assessable.
- **Alternatives considered**: Evaluating all targets without order; treating Microsoft SQL or Oracle-on-Azure options as one combined target.

## Decision: Standards baseline

- **Chosen**: Use the Microsoft Cloud Adoption Framework and Azure Well-Architected Framework as cross-target decision dimensions; use official Azure product capability and migration guidance for PostgreSQL, Azure SQL Managed Instance and SQL Server on Azure VMs; use Oracle Maximum Availability Architecture and the applicable Oracle Database@Azure service guidance for the Oracle branch.
- **Rationale**: Separates common governance, reliability, security, cost and operations gates from product-specific compatibility rules.
- **Alternatives considered**: One undifferentiated checklist; AI-only recommendations; collector-section presence as a proxy for standards compliance.

## Decision: Deterministic assessment before narrative generation

- **Chosen**: Versioned deterministic rules produce gate outcomes, findings and target progression; AI may explain those outcomes but cannot create or override them.
- **Rationale**: Recommendations must be reproducible, testable and traceable when model availability or output varies.
- **Alternatives considered**: Prompt-only target selection; hard-coded report prose.

## Decision: Questionnaire evidence

- **Chosen**: Database-scoped questionnaire answers supplement machine evidence for vendor support, licensing, ownership, business constraints, recovery, security, cost and approvals.
- **Rationale**: These facts are not reliably observable from Oracle catalog views.
- **Alternatives considered**: Collector-only assessment; project-wide answers for all databases.

## Decision: Evidence conflicts

- **Chosen**: Preserve both sources and require explicit resolution; no source silently overrides another.
- **Rationale**: Installed features, licensed features, active use and stakeholder declarations are materially different facts.
- **Alternatives considered**: Machine evidence always wins; latest response always wins.

## Decision: Discovery governance

- **Chosen**: Discovery creates candidates that require accept/reject review before becoming authoritative graph edges.
- **Rationale**: Database-link descriptors, synonyms and stakeholder assertions can be incomplete, aliased or stale.
- **Alternatives considered**: Immediate publication; keeping discovery outside the persisted graph.

## Decision: Compatibility rollout

- **Chosen**: Preserve existing graph and portfolio contracts while new candidate and suggestion APIs are introduced; migrate existing manual records without data loss before retiring compatibility behavior.
- **Rationale**: Existing user-authored topology and grouping information is valuable evidence.
- **Alternatives considered**: Replace existing tables and routes in one release.

# Architecture Index

## Implementation Guide

This index is not the full contract. Do not implement from this file alone; follow the artifact paths below.

### Global artifacts

- `unit_graph.yaml`: unit boundaries, entry points, dependencies and source anchors. Source anchors are not rewrite targets.
- `migration_boundary.yaml`: binding implementation scope and compatibility constraints.
- `wire_contracts.yaml`: filter rows by assigned unit and preserve frozen/must-preserve contracts.
- `shared_modules.yaml`: filter `used_by_units`; respect each unit's `used_fields` subset.
- `cross_unit_state.yaml`: filter flows whose writer or reader matches the assigned unit.
- `seams.yaml`: observe frozen-side rules and concrete bridge mappings.
- `project-structure.md`, `tech-stack.md`, `data-model.md`: current architecture context for planning.

### Units

For each unit below, read `units/<unit>/behavior.yaml`, `bindings.yaml`, and `unit_decomposition.yaml`, then filter every global artifact by that unit:

- `oracle-collector` — agent Oracle job execution.
- `agent-result-submission` — signed result ingestion.
- `questionnaire-api` — stakeholder evidence capture.
- `report-generation-api` — evidence bundle and report generation.
- `graph-api` — authoritative communication graph.
- `portfolio-api` — persisted database groupings.
- `communication-map-page` — graph portal journey.
- `portfolio-page` — portfolio portal journey.

Before reporting completion, implementation agents must list artifacts read, implemented `must_preserve` items, unresolved or deferred contracts, and test/build/runtime evidence.

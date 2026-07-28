# UI/UX Specification

_Assessment Toolkit | Portal structure, user journeys and screen-level requirements_

## 1. Product experience goal

The portal should feel like a professional assessment workspace for architects, database owners, application owners and delivery teams. It should make complex estate discovery manageable through clear navigation, evidence status, portfolio grouping and communication-map visuals.

## 2. Primary personas

| Persona | Needs |
| --- | --- |
| Customer architect | Understand scope, dependencies, risks and target recommendations. |
| Database owner | Provide database details, review findings and confirm technical constraints. |
| Application owner | Validate dependencies, downtime windows and communication flows. |
| Factory or partner engineer | Run discovery, review evidence, build wave plans and generate reports. |
| Reviewer/approver | Review final deliverables, sign off and export approved outputs. |

## 3. Information architecture

- Dashboard: project status, evidence completeness, risks and next actions.
- Customers and Projects: workspace setup and configuration.
- Environments: production, UAT, DR, dev and custom environments.
- Inventory: databases and optional related applications/services.
- Questionnaires: business and technical data collection.
- Assessment Agents: registration, health, jobs and results.
- Evidence Library: uploaded reports, raw results and approved deliverables.
- Portfolios: grouping, readiness and migration scope.
- Communication Maps: dependencies, flows and validation states.
- Reports: draft generation, review, approval and export.

## 4. Key user journeys

| Journey | Main steps | Success outcome |
| --- | --- | --- |
| Create project | Create customer, project, deployment mode, storage location | Empty project workspace is ready. |
| Collect questionnaire | Assign sections, save progress, validate completeness | Required baseline context is captured. |
| Register agent | Create bootstrap package, deploy agent, verify heartbeat | Agent is ready for assessment jobs. |
| Upload evidence | Upload report, parse, review extracted values | Evidence appears in project inventory. |
| Build portfolio | Select grouping logic, review members, save portfolio | Database group is ready for planning. |
| Validate map | Review candidate dependencies, confirm or reject edges | Communication map reaches approved version. |
| Generate report | Select evidence bundle, generate draft, review, approve | Final deliverable is exported to configured storage. |

## 5. Screen-level requirements

| Screen | Required elements |
| --- | --- |
| Project dashboard | Completion score, evidence status, open risks, agents online/offline, recent activities. |
| Questionnaire | Section progress, required fields, save draft, validation errors, reviewer comments. |
| Agent management | Agent status, plugin list, last heartbeat, jobs, bootstrap package state. |
| Inventory | Filter by environment, engine, criticality, owner, portfolio and readiness. |
| Portfolio view | Grouping rules, member list, risk summary, dependency constraints and wave assignment. |
| Communication map | Graph canvas, filters, edge confidence, source evidence panel and validation actions. |
| Report review | Draft sections, source traceability, comments, approval and export target. |

## 6. UX principles

- Show evidence confidence everywhere decisions are made.
- Separate draft, reviewed and approved states visually.
- Prefer guided flows for first-time users but allow expert shortcuts.
- Keep raw evidence separate from approved outputs.
- Use filters and progressive disclosure for large database estates.
- Avoid forcing users to understand implementation details such as graph tables or parser internals.

## 7. Accessibility and usability

- Keyboard navigation for forms and grids.
- Clear status labels in addition to colour.
- Readable graph alternatives such as dependency tables and exportable lists.
- Error messages that explain what to fix and where.
- Autosave or explicit save-draft behaviour for long questionnaires.
- Responsive layout for common laptop screen sizes used during workshops.

## 8. MVP screens

- Project dashboard
- Environment setup
- Questionnaire
- Agent management
- Evidence upload/library
- Database inventory
- Portfolio grouping
- Communication map viewer
- Report generation and review

# Known Limitations

**Reviewed:** 2026-09-02

This document is part of the current system contract. Items listed here must not be represented as implemented, production-certified or fully automated.

## Identity and user administration

- Authentication uses application-managed cookies, not Microsoft Entra ID federation.
- User and project-membership administration exist only as APIs; there is no management screen.
- Password reset, user deletion, platform-role changes and self-service profile management are absent.
- There is no documented account lockout, MFA or external identity lifecycle integration.

## Authorization and audit

- Project and environment membership authorization is implemented, but complete UI affordances for governance are absent.
- Object-level scope resolution is incomplete for questionnaire-response and graph-edge ID routes, multipart evidence/import requests, and some global or creation APIs.
- Successful non-authentication requests using methods other than GET, HEAD and OPTIONS are audited at the application layer. GET-side mutations such as agent job assignment are not audited.
- Audit rows are not protected by database-enforced append-only permissions, tamper-evident chaining or external immutable retention.
- Production rate limiting is not implemented.

## Agent security and certification

- Seven plugin families are implemented, but only PostgreSQL has repository end-to-end coverage.
- Other engines require testing against supported live versions, permissions and topology variants before production claims.
- Manually registered raw PSKs live only in API process configuration; after restart they must be supplied explicitly or the agent must be re-registered.
- Durable agent key storage, rotation and acknowledgement workflows are not implemented.
- Offline collector results are validated structurally but are not cryptographically signed and are marked `Unverified`.
- Controlled-media transfer, collector code signing and offline package integrity remain operational responsibilities outside the application.

## Discovery, graph and planning

- Communication maps are manually authored database-to-database edges.
- Automatic connection discovery and candidate-edge review are absent.
- Applications, business services, generic topology nodes and evidence-backed edge validation are absent.
- Portfolios are manual database ID groups, not dependency-aware migration waves.
- Risk-register, recommendation and migration-wave persistence are absent.

## AI and reports

- Report generation depends on a configured Microsoft Foundry/Azure OpenAI-compatible model and a successful real connectivity test.
- There is no deterministic rules-only or local-model fallback.
- Generated output should be reviewed by a qualified migration practitioner.
- Persisted reports do not currently record a report-contract version; legacy malformed rows are shown as unavailable and cannot advance through review or export in the portal.
- Report export is browser-generated JSON followed by a state transition.
- Report-instruction edits have optimistic concurrency and are captured in new evidence bundles, but the application does not provide policy version history, diff, approval or rollback workflows.
- PDF generation, expiring share links, section comments, section locking and server-side publishing are absent.
- Sending evidence to a model endpoint requires customer-data and regional-compliance approval outside the application.

## Storage and data lifecycle

- Local evidence uses a filesystem-backed Docker volume.
- Azure infrastructure mounts Azure Files; there is no general pluggable storage abstraction in the application.
- Blob publishing, SharePoint/OneDrive publishing and configurable retention policies are absent.
- Local agent database credentials are plaintext in `local-agent/databases.json`.
- Local and Azure data stores are independent; application deployment does not synchronize them.

## Portal behavior

- Some dashboard counts are based on the first accessible project while labels appear estate-wide.
- There is no portal user or membership administration screen/route; backend APIs exist.
- Graph and portfolio screens expose manual current capabilities, not the broader target designs in legacy specifications.
- Accessibility, browser compatibility and responsive behavior have not been validated by a comprehensive automated suite.

## Testing and delivery

- The repository does not contain a broad backend unit/integration test suite.
- Frontend unit tests and Playwright regression tests are absent.
- Connected database E2E coverage is limited to PostgreSQL.
- There is no complete CI/CD pipeline represented in the repository.
- Production security testing, load testing and failure-recovery testing are incomplete.
- A complete tested backup/restore, disaster recovery and incident response runbook is absent.

## Azure deployment

- Bicep declarations are not proof that resources are currently deployed or healthy.
- Default Bicep container images point to a hello-world sample unless exact application images are supplied.
- `configureSecrets` defaults to `false`; application deployments must intentionally enable and provide required secrets.
- Production monitoring, alerting, private access validation, scaling policy validation and restore testing require environment-specific completion.

## Criteria for changing this document

Remove or narrow a limitation only when all of the following are available:

1. Implemented code and configuration.
2. Focused automated or repeatable runtime validation.
3. Updated operating guidance.
4. Defined security and failure behavior.
5. Representative environment or engine certification where applicable.
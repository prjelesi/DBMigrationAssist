# Banana Inc Security and Compliance

This document defines fictional requirements for assessment. Final controls require Banana Inc security, privacy and platform approval.

## Data classification

| Class | Examples | Systems | Minimum handling |
| --- | --- | --- | --- |
| Restricted personal | Customer contact details, employee and payroll data | Customer DB, HR DB | Strong access approval, masking outside production, audited privileged access |
| Restricted financial | Ledger, invoices, bank references and payment references | Finance DB, Commerce DB | Encryption, reconciliation, segregation of duties, retained audit trail |
| Confidential operational | Inventory, pricing, suppliers and partner messages | Warehouse, Integration, Reporting | Least privilege, private networking, controlled export |
| Internal | Technical metadata and sanitized assessment output | Toolkit evidence | Approved project access and retention policy |

The assessment agent should collect metadata, configuration and performance evidence, not table contents. Review generated scripts and evidence before transfer.

## Identity and access

- Use dedicated read-only Oracle assessment accounts with time-limited access.
- Store migration and database credentials in Key Vault; never place them in workbooks or evidence files.
- Prefer managed identities for Azure services and Entra authentication where the target supports it.
- Use separate application identities per workload and environment.
- Enforce privileged access workflows, MFA and just-in-time VM access for administrators.
- Separate database administration, security administration and report approval duties.
- Review vendor support identities and remove them after the migration warranty period.

## Network security

- Keep PostgreSQL, SQL and Oracle VM targets on private networks.
- Deny public network access unless an approved exception has compensating controls and an expiry date.
- Restrict NSGs and firewall policies to documented application and migration flows.
- Centralize DNS through approved private resolvers and prevent unapproved data exfiltration paths.
- Capture firewall, NSG flow and private endpoint diagnostics in the security monitoring workspace.

## Encryption and secrets

- Require TLS for all application, assessment and migration connections.
- Confirm Oracle native network encryption for source and fallback traffic.
- Use platform encryption at rest; assess customer-managed keys for restricted datasets based on policy, not assumption.
- Define key ownership, rotation, recovery and deletion responsibilities before production.
- Persist ASP.NET Core Data Protection keys used by the toolkit and protect their backup with the database backup.

## Logging and detection

- Send Azure platform, database audit, firewall, Key Vault and VM security events to centralized Log Analytics/SIEM.
- Define alerts for failed privileged sign-ins, firewall changes, unusual exports, disabled auditing and replication lag.
- Prevent secrets, SQL text containing personal data and row-level payloads from entering general application logs.
- Synchronize time and retain logs according to financial, privacy and incident-response requirements.
- Enable Defender for Cloud recommendations and document accepted exceptions.

## Data migration controls

1. Approve tools, accounts, source/target paths and staging locations before data movement.
2. Keep migration workers and staging storage in Banana Inc-controlled subscriptions.
3. Encrypt temporary files and remove them through a verified disposal process after reconciliation.
4. Reconcile row counts, checksums, financial control totals and rejected records.
5. Record who approved each cutover, rollback and production-access decision.
6. Mask or synthesize personal data in development and migration rehearsal environments.

## Security evidence checklist

- Data protection impact assessment and data-flow approval.
- Source and target access matrices.
- Vendor support and privileged-access model.
- Encryption configuration and key-management decision.
- Network rule export and private DNS design.
- Audit categories, destinations, retention and alert tests.
- Backup/restore and cyber-recovery test evidence.
- Vulnerability, patch and hardening reports for migration workers and Oracle VMs.
- Data reconciliation and temporary-data destruction evidence.
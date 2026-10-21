# Security policy

## Supported code

Security fixes target the current `main` branch. There are no maintained
historical release branches or guaranteed remediation timelines.

## Reporting a vulnerability

Use **Security > Advisories > Report a vulnerability** in this GitHub repository
when private vulnerability reporting is available. Include the affected commit,
impact, prerequisites, and a minimal reproduction using synthetic data.

If the private reporting button is not available, do not disclose the
vulnerability in a public issue. Wait for a private reporting channel to be
enabled. Do not send credentials, real customer evidence, or production data.

## Safe operation

- Run assessments only against systems you are authorized to inspect.
- Treat evidence, reports, inventories, and agent bootstrap packages as sensitive.
- Use unique credentials, least-privilege database accounts, HTTPS, and durable,
  access-controlled Data Protection keys.
- Docker Compose is a local development configuration, not a hardened production
  deployment. Do not expose its database or development API ports to the internet.
- AI-enabled reporting sends assessment information to the configured model
  provider. Obtain appropriate authorization and verify provider and data-handling
  settings before processing customer information.
- Rotate any exposed credential immediately. Deleting a file or rewriting Git
  history does not revoke a credential.

See the [architecture and security documentation](docs/current/ARCHITECTURE_AND_SECURITY.md)
and [operations guidance](docs/current/OPERATIONS_AND_DEPLOYMENT.md).

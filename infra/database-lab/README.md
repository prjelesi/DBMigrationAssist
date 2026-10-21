# Database source lab

This subscription-scope Bicep deployment creates a disposable resource group containing two Linux VMs and six seeded source database engines. It is separate from `infra/main.bicep` and does not deploy monitoring resources.

## Prerequisites

- Azure CLI authenticated to your intended lab subscription. Verify the account
  and select the subscription explicitly before deployment.
- Contributor permissions for resource creation and permission to create the Key Vault role assignment.
- A public SSH key and an administrator source CIDR.
- Two synthetic passwords of at least 12 characters, each containing uppercase, lowercase, numeric, and special characters. Do not reuse production credentials.

Set the parameter values in the current PowerShell session:

```powershell
$env:DBMLAB_ADMIN_SSH_PUBLIC_KEY = Get-Content "$HOME/.ssh/id_ed25519.pub" -Raw
$env:DBMLAB_DATABASE_ADMIN_PASSWORD = Read-Host 'Database lab password' -MaskInput
$env:DBMLAB_ORACLE_SYS_PASSWORD = Read-Host 'Oracle SYS password' -MaskInput
```

Replace the example `adminSourceCidr` in `main.bicepparam`, then validate:

```powershell
az bicep build --file infra/database-lab/main.bicep
az bicep build-params --file infra/database-lab/main.bicepparam
```

Deployment is intentionally manual:

```powershell
az deployment sub create `
  --name dbmigration-source-lab `
  --location eastus2 `
  --parameters infra/database-lab/main.bicepparam
```

Database listeners are private at `10.40.1.10` and `10.40.1.20`. Only SSH is reachable through the public IPs, restricted by `adminSourceCidr`. Bootstrap completion is recorded at `/opt/dbmigration-lab/READY`; detailed logs are under `/var/log/dbmigration-*-bootstrap.log`.

Oracle XE 21c supports Oracle Linux 7 and 8, so the Oracle host uses the pinned East US 2 image `Oracle:Oracle-Linux:ol810-lvm-gen2:8.10.9`. The image is Gen2 and advertises Trusted Launch and accelerated-networking support.
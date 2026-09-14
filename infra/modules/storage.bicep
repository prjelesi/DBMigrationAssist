param location string
param tags object
param storageAccountName string
param containerAppsSubnetId string

// Single NFS-protocol Azure Files share backing all app-data mount points (evidence,
// data-protection, local-agent, report-config live as sub-directories on this share).
// NFS shares authenticate purely via network rules (VNet/service endpoint), never via
// the storage account key, so this configuration keeps working even when organizational
// policy enforces `allowSharedKeyAccess = false` on storage accounts (see
// docs/decisions for the incident that prompted this: SMB mounts required the account
// key and broke when the policy disabled shared-key access).
var appDataShareName = 'appdata'

resource storageAccount 'Microsoft.Storage/storageAccounts@2026-04-01' = {
  name: storageAccountName
  location: location
  tags: tags
  kind: 'FileStorage'
  sku: {
    name: 'Premium_LRS'
  }
  properties: {
    allowBlobPublicAccess: false
    allowCrossTenantReplication: false
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Enabled'
    // NFS 4.1 (used exclusively by this account) is mounted by Container Apps using the
    // plain kernel NFS client, which does not speak TLS/HTTPS. "Secure transfer required"
    // must stay disabled here or every NFS mount fails with "access denied by server" -
    // this is not a security regression because the account has no SMB/REST clients and
    // access is already restricted to the container-apps subnet via the network rule below.
    supportsHttpsTrafficOnly: false
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      virtualNetworkRules: [
        {
          action: 'Allow'
          id: containerAppsSubnetId
        }
      ]
    }
  }
}

resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2026-04-01' = {
  parent: storageAccount
  name: 'default'
  properties: {}
}

resource appDataShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2026-04-01' = {
  parent: fileService
  name: appDataShareName
  properties: {
    enabledProtocols: 'NFS'
    rootSquash: 'NoRootSquash'
    shareQuota: 100
  }
}

output id string = storageAccount.id
output name string = storageAccount.name
output appDataShareName string = appDataShare.name

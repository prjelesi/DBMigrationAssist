param location string
param tags object
param storageAccountName string
param containerAppsSubnetId string

var evidenceShareName = 'evidence'
var dataProtectionShareName = 'data-protection'
var localAgentShareName = 'local-agent'

resource storageAccount 'Microsoft.Storage/storageAccounts@2026-04-01' = {
  name: storageAccountName
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowCrossTenantReplication: false
    allowSharedKeyAccess: true
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Enabled'
    supportsHttpsTrafficOnly: true
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

resource evidenceShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2026-04-01' = {
  parent: fileService
  name: evidenceShareName
  properties: {
    accessTier: 'Hot'
    enabledProtocols: 'SMB'
    shareQuota: 10
  }
}

resource dataProtectionShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2026-04-01' = {
  parent: fileService
  name: dataProtectionShareName
  properties: {
    accessTier: 'Hot'
    enabledProtocols: 'SMB'
    shareQuota: 5
  }
}

resource localAgentShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2026-04-01' = {
  parent: fileService
  name: localAgentShareName
  properties: {
    accessTier: 'Hot'
    enabledProtocols: 'SMB'
    shareQuota: 5
  }
}

output id string = storageAccount.id
output name string = storageAccount.name
output evidenceShareName string = evidenceShare.name
output dataProtectionShareName string = dataProtectionShare.name
output localAgentShareName string = localAgentShare.name

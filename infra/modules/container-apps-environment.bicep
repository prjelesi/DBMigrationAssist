param location string
param tags object
param containerAppsEnvironmentName string
param infrastructureSubnetId string
param storageAccountName string
param appDataShareName string

var appDataFileHost = '${storageAccountName}.file.${environment().suffixes.storage}'

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2025-01-01' = {
  name: containerAppsEnvironmentName
  location: location
  tags: tags
  properties: {
    vnetConfiguration: {
      infrastructureSubnetId: infrastructureSubnetId
      internal: false
    }
  }
}

// NFS mount: authenticated purely by the container app subnet's network rule on the
// storage account, no storage account key involved. Immune to policies that disable
// shared-key access. App containers mount this single share multiple times using
// different subPath values (see api-container-app.bicep / agent-container-app.bicep).
resource appDataStorage 'Microsoft.App/managedEnvironments/storages@2025-01-01' = {
  parent: containerAppsEnvironment
  name: 'appdata'
  properties: {
    nfsAzureFile: {
      accessMode: 'ReadWrite'
      server: appDataFileHost
      shareName: '/${storageAccountName}/${appDataShareName}'
    }
  }
}

output id string = containerAppsEnvironment.id
output defaultDomain string = containerAppsEnvironment.properties.defaultDomain

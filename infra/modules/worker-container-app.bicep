param location string
param tags object
param containerAppName string
param containerAppsEnvironmentId string
param containerRegistryLoginServer string
param managedIdentityId string
param keyVaultName string
param apiBaseUrl string
param containerImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

var placeholderImage = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
var isPlaceholder = containerImage == placeholderImage

resource containerApp 'Microsoft.App/containerApps@2026-01-01' = {
  name: containerAppName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  }
  properties: {
    environmentId: containerAppsEnvironmentId
    configuration: {
      activeRevisionsMode: 'Single'
      registries: isPlaceholder ? [] : [
        { identity: managedIdentityId, server: containerRegistryLoginServer }
      ]
      secrets: isPlaceholder ? [] : [
        {
          identity: managedIdentityId
          #disable-next-line no-hardcoded-env-urls
          keyVaultUrl: 'https://${keyVaultName}.vault.azure.net/secrets/postgres-connection-string'
          name: 'postgres-connection-string'
        }
        {
          identity: managedIdentityId
          #disable-next-line no-hardcoded-env-urls
          keyVaultUrl: 'https://${keyVaultName}.vault.azure.net/secrets/worker-service-token'
          name: 'worker-service-token'
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'worker'
          image: containerImage
          env: concat([
            { name: 'ASPNETCORE_ENVIRONMENT', value: 'Production' }
            { name: 'Worker__ApiBaseUrl', value: apiBaseUrl }
          ], isPlaceholder ? [] : [
            { name: 'ConnectionStrings__Postgres', secretRef: 'postgres-connection-string' }
            { name: 'Worker__ServiceToken', secretRef: 'worker-service-token' }
          ])
          resources: { cpu: json('0.5'), memory: '1Gi' }
        }
      ]
      scale: { maxReplicas: 1, minReplicas: 1 }
    }
  }
}

param location string
param tags object
param containerAppName string
param containerAppsEnvironmentId string
param containerRegistryLoginServer string
param managedIdentityId string
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
    }
    template: {
      containers: [
        {
          name: 'agent'
          image: containerImage
          env: [
            { name: 'AGENT_AUTO_REGISTER', value: 'true' }
            { name: 'AGENT_BOOTSTRAP_PATH', value: '/app/bootstrap/bootstrap.json' }
          ]
          resources: { cpu: json('0.5'), memory: '1Gi' }
          volumeMounts: [
            { mountPath: '/app/bootstrap', volumeName: 'local-agent' }
          ]
        }
      ]
      scale: { maxReplicas: 1, minReplicas: 1 }
      volumes: [
        { name: 'local-agent', storageName: 'local-agent', storageType: 'AzureFile' }
      ]
    }
  }
}

output id string = containerApp.id

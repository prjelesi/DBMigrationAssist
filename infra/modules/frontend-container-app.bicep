param location string
param tags object
param containerAppName string
param containerAppsEnvironmentId string
param containerRegistryLoginServer string
param managedIdentityId string
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
      ingress: { allowInsecure: false, external: true, targetPort: 80, transport: 'auto' }
      registries: isPlaceholder ? [] : [
        { identity: managedIdentityId, server: containerRegistryLoginServer }
      ]
      secrets: []
    }
    template: {
      containers: [
        {
          name: 'frontend'
          image: containerImage
          env: [
            { name: 'API_UPSTREAM', value: apiBaseUrl }
          ]
          probes: [
            {
              type: 'Liveness'
              httpGet: { path: '/', port: 80, scheme: 'HTTP' }
              initialDelaySeconds: 5
              periodSeconds: 20
            }
            {
              type: 'Readiness'
              httpGet: { path: '/', port: 80, scheme: 'HTTP' }
              initialDelaySeconds: 2
              periodSeconds: 10
            }
          ]
          resources: { cpu: json('0.25'), memory: '0.5Gi' }
        }
      ]
      scale: { maxReplicas: 1, minReplicas: 1 }
    }
  }
}

output id string = containerApp.id
output url string = 'https://${containerApp.properties.configuration.ingress.fqdn}'

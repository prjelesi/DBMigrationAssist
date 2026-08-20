param location string
param tags object
param containerAppName string
param containerAppsEnvironmentId string
param containerAppsEnvironmentDefaultDomain string
param containerRegistryLoginServer string
param managedIdentityId string
param keyVaultName string
param containerImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
param appAdminEmail string
param appAdminDisplayName string

var placeholderImage = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
var isPlaceholder = containerImage == placeholderImage
var appPort = 8080
var effectivePort = isPlaceholder ? 80 : appPort
var apiUrl = 'https://${containerAppName}.${containerAppsEnvironmentDefaultDomain}'

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
      ingress: {
        allowInsecure: false
        external: true
        targetPort: effectivePort
        transport: 'auto'
      }
      registries: isPlaceholder ? [] : [
        {
          identity: managedIdentityId
          server: containerRegistryLoginServer
        }
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
          keyVaultUrl: 'https://${keyVaultName}.vault.azure.net/secrets/app-admin-password'
          name: 'app-admin-password'
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
          name: 'api'
          image: containerImage
          env: concat([
            { name: 'ASPNETCORE_ENVIRONMENT', value: 'Production' }
            { name: 'PORT', value: string(effectivePort) }
            { name: 'Api__PublicUrl', value: apiUrl }
            { name: 'Evidence__StorageRoot', value: '/app/evidence' }
            { name: 'DataProtection__KeysPath', value: '/app/data-protection' }
            { name: 'LocalAgent__BootstrapPath', value: '/app/local-agent/bootstrap.json' }
            { name: 'LocalAgent__BackendUrl', value: apiUrl }
            { name: 'AppAdmin__Email', value: appAdminEmail }
            { name: 'AppAdmin__DisplayName', value: appAdminDisplayName }
          ], isPlaceholder ? [] : [
            { name: 'ConnectionStrings__Postgres', secretRef: 'postgres-connection-string' }
            { name: 'AppAdmin__Password', secretRef: 'app-admin-password' }
            { name: 'Worker__ServiceToken', secretRef: 'worker-service-token' }
          ])
          probes: [
            {
              type: 'Liveness'
              httpGet: { path: isPlaceholder ? '/' : '/health', port: effectivePort, scheme: 'HTTP' }
              initialDelaySeconds: 15
              periodSeconds: 20
            }
            {
              type: 'Readiness'
              httpGet: { path: isPlaceholder ? '/' : '/health', port: effectivePort, scheme: 'HTTP' }
              initialDelaySeconds: 5
              periodSeconds: 10
            }
          ]
          resources: { cpu: json('0.5'), memory: '1Gi' }
          volumeMounts: [
            { mountPath: '/app/evidence', volumeName: 'evidence' }
            { mountPath: '/app/data-protection', volumeName: 'data-protection' }
            { mountPath: '/app/local-agent', volumeName: 'local-agent' }
          ]
        }
      ]
      scale: { maxReplicas: 1, minReplicas: 1 }
      volumes: [
        { name: 'evidence', storageName: 'evidence', storageType: 'AzureFile' }
        { name: 'data-protection', storageName: 'data-protection', storageType: 'AzureFile' }
        { name: 'local-agent', storageName: 'local-agent', storageType: 'AzureFile' }
      ]
    }
  }
}

output id string = containerApp.id
output url string = apiUrl

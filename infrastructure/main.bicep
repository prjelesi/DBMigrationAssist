@description('Azure region')
param location string = resourceGroup().location

@description('Base name used for all resources (ACR name must be globally unique)')
param baseName string = 'dbmigassess'

@description('API key for the assessment engine')
@secure()
param apiKey string

@description('Dataverse URL (optional)')
param dataverseUrl string = ''

@description('Entra ID client ID for Dataverse auth (optional)')
param azureClientId string = ''

@description('Entra ID client secret for Dataverse auth (optional)')
@secure()
param azureClientSecret string = ''

@description('Entra ID tenant ID (optional)')
param azureTenantId string = ''

@description('Power Automate callback webhook URL (optional)')
param callbackWebhookUrl string = ''

@description('Existing VNet name to integrate with (e.g. vnet-demo)')
param existingVnetName string = ''

@description('Existing subnet name for ACA VNet integration')
param existingSubnetName string = ''

@description('Container image tag to deploy')
param imageTag string = 'latest'

var acrName = 'assess${replace(baseName, '-', '')}acr'
var acaEnvName = '${baseName}-aca-env'
var acaAppName = '${baseName}-app'
var logWorkspaceName = '${baseName}-logs'

// ── Log Analytics ─────────────────────────────────────────────────────────────
resource logWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logWorkspaceName
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

// ── Azure Container Registry ──────────────────────────────────────────────────
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  sku: { name: 'Basic' }
  properties: {
    adminUserEnabled: true
    publicNetworkAccess: 'Enabled'
  }
}

// ── Container Apps Environment ────────────────────────────────────────────────
resource acaEnv 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: acaEnvName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logWorkspace.properties.customerId
        sharedKey: logWorkspace.listKeys().primarySharedKey
      }
    }
    // VNet integration — only if existing VNet/subnet provided
    vnetConfiguration: empty(existingVnetName) ? null : {
      infrastructureSubnetId: resourceId('Microsoft.Network/virtualNetworks/subnets',
        existingVnetName, existingSubnetName)
      internal: false
    }
  }
}

// ── Container App ─────────────────────────────────────────────────────────────
resource acaApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: acaAppName
  location: location
  identity: { type: 'SystemAssigned' }
  properties: {
    managedEnvironmentId: acaEnv.id
    configuration: {
      ingress: {
        external: true
        targetPort: 8000
        transport: 'http'
        allowInsecure: false
      }
      registries: [
        {
          server: acr.properties.loginServer
          username: acr.listCredentials().username
          passwordSecretRef: 'acr-password'
        }
      ]
      secrets: [
        { name: 'acr-password',       value: acr.listCredentials().passwords[0].value }
        { name: 'api-key',            value: apiKey }
        { name: 'azure-client-secret',value: empty(azureClientSecret) ? 'not-set' : azureClientSecret }
      ]
    }
    template: {
      containers: [
        {
          name: 'assessment-engine'
          image: '${acr.properties.loginServer}/db-migration-assessment:${imageTag}'
          resources: {
            cpu: json('1.0')
            memory: '2Gi'
          }
          env: [
            { name: 'API_KEY',              secretRef: 'api-key' }
            { name: 'DATAVERSE_URL',        value: dataverseUrl }
            { name: 'AZURE_CLIENT_ID',      value: azureClientId }
            { name: 'AZURE_CLIENT_SECRET',  secretRef: 'azure-client-secret' }
            { name: 'AZURE_TENANT_ID',      value: azureTenantId }
            { name: 'CALLBACK_WEBHOOK_URL', value: callbackWebhookUrl }
          ]
          probes: [
            {
              type: 'Liveness'
              httpGet: { path: '/health', port: 8000 }
              initialDelaySeconds: 20
              periodSeconds: 30
            }
            {
              type: 'Readiness'
              httpGet: { path: '/health', port: 8000 }
              initialDelaySeconds: 10
              periodSeconds: 10
            }
          ]
        }
      ]
      scale: {
        minReplicas: 0   // Scale to zero when idle
        maxReplicas: 3
        rules: [
          {
            name: 'http-scaling'
            http: { metadata: { concurrentRequests: '10' } }
          }
        ]
      }
    }
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────
output acrLoginServer string = acr.properties.loginServer
output acrName string = acr.name
output apiUrl string = 'https://${acaApp.properties.configuration.ingress.fqdn}'
output healthUrl string = 'https://${acaApp.properties.configuration.ingress.fqdn}/health'
output docsUrl string = 'https://${acaApp.properties.configuration.ingress.fqdn}/docs'
output dockerPushCommand string = 'docker push ${acr.properties.loginServer}/db-migration-assessment:${imageTag}'
output acrUsername string = acr.listCredentials().username

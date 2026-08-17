@description('Assessment Toolkit — Azure Container Apps deployment')
param location string = resourceGroup().location
param environmentName string = 'assessment-toolkit'

@secure()
param postgresAdminPassword string

@secure()
param acrPassword string
param acrServer string
param acrUsername string

@description('Enable Microsoft Entra authentication for the portal API.')
param authenticationEnabled bool = false

@description('Microsoft Entra tenant ID. Required when authentication is enabled.')
param entraTenantId string = ''

@description('Client ID of the Microsoft Entra API app registration. Required when authentication is enabled.')
param entraApiClientId string = ''

@description('Client ID of the Microsoft Entra SPA app registration. Required when authentication is enabled.')
param entraSpaClientId string = ''

@description('Delegated API scope exposed by the API app registration. Required when authentication is enabled.')
param entraApiScope string = ''

var resourceToken = uniqueString(subscription().id, resourceGroup().id, location, environmentName)

// ── Container Apps Environment ─────────────────────────────────────────────
resource logWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${environmentName}-logs'
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

resource acaEnv 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: '${environmentName}-env'
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logWorkspace.properties.customerId
        sharedKey: logWorkspace.listKeys().primarySharedKey
      }
    }
  }
}

// ── PostgreSQL Flexible Server ──────────────────────────────────────────────
resource postgres 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: '${environmentName}-pg-${resourceToken}'
  location: location
  sku: { name: 'Standard_B1ms', tier: 'Burstable' }
  properties: {
    administratorLogin: 'assessment'
    administratorLoginPassword: postgresAdminPassword
    version: '16'
    storage: { storageSizeGB: 32 }
    backup: { backupRetentionDays: 7, geoRedundantBackup: 'Disabled' }
    highAvailability: { mode: 'Disabled' }
  }
}

resource postgresDb 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2024-08-01' = {
  parent: postgres
  name: 'assessmentdb'
}

resource postgresAzureServicesFirewall 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2024-08-01' = {
  parent: postgres
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

var postgresConnString = 'Host=${postgres.properties.fullyQualifiedDomainName};Port=5432;Database=assessmentdb;Username=assessment;Password=${postgresAdminPassword};SslMode=Require'

// ── API Container App ───────────────────────────────────────────────────────
resource apiApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: '${environmentName}-api'
  location: location
  properties: {
    managedEnvironmentId: acaEnv.id
    configuration: {
      ingress: {
        external: true
        targetPort: 8080
        transport: 'http'
      }
      registries: [{
        server: acrServer
        username: acrUsername
        passwordSecretRef: 'acr-password'
      }]
      secrets: [
        { name: 'acr-password', value: acrPassword }
        { name: 'postgres-conn', value: postgresConnString }
      ]
    }
    template: {
      containers: [{
        name: 'api'
        image: '${acrServer}/dbmr-api:latest'
        resources: { cpu: json('0.5'), memory: '1Gi' }
        env: [
          { name: 'ASPNETCORE_ENVIRONMENT', value: 'Production' }
          { name: 'ConnectionStrings__Postgres', secretRef: 'postgres-conn' }
          { name: 'Api__PublicUrl', value: 'https://${environmentName}-api.${acaEnv.properties.defaultDomain}' }
          { name: 'Authentication__Enabled', value: string(authenticationEnabled) }
          { name: 'AzureAd__TenantId', value: entraTenantId }
          { name: 'AzureAd__ClientId', value: entraApiClientId }
          { name: 'Authentication__SpaClientId', value: entraSpaClientId }
          { name: 'Authentication__ApiScope', value: entraApiScope }
        ]
      }]
      scale: { minReplicas: 1, maxReplicas: 3 }
    }
  }
}

// ── Worker Container App ────────────────────────────────────────────────────
resource workerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: '${environmentName}-worker'
  location: location
  properties: {
    managedEnvironmentId: acaEnv.id
    configuration: {
      registries: [{
        server: acrServer
        username: acrUsername
        passwordSecretRef: 'acr-password'
      }]
      secrets: [
        { name: 'acr-password', value: acrPassword }
        { name: 'postgres-conn', value: postgresConnString }
      ]
    }
    template: {
      containers: [{
        name: 'worker'
        image: '${acrServer}/dbmr-worker:latest'
        resources: { cpu: json('0.5'), memory: '1Gi' }
        env: [
          { name: 'ASPNETCORE_ENVIRONMENT', value: 'Production' }
          { name: 'ConnectionStrings__Postgres', secretRef: 'postgres-conn' }
          { name: 'Worker__ApiBaseUrl', value: 'https://${environmentName}-api.${acaEnv.properties.defaultDomain}' }
        ]
      }]
      scale: { minReplicas: 1, maxReplicas: 5 }
    }
  }
}

// ── Frontend Container App ──────────────────────────────────────────────────
resource frontendApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: '${environmentName}-frontend'
  location: location
  properties: {
    managedEnvironmentId: acaEnv.id
    configuration: {
      ingress: {
        external: true
        targetPort: 80
        transport: 'http'
      }
      registries: [{
        server: acrServer
        username: acrUsername
        passwordSecretRef: 'acr-password'
      }]
      secrets: [{ name: 'acr-password', value: acrPassword }]
    }
    template: {
      containers: [{
        name: 'frontend'
        image: '${acrServer}/dbmr-frontend:latest'
        resources: { cpu: json('0.25'), memory: '0.5Gi' }
        env: [{ name: 'API_UPSTREAM', value: 'https://${environmentName}-api.${acaEnv.properties.defaultDomain}' }]
      }]
      scale: { minReplicas: 1, maxReplicas: 2 }
    }
  }
}

// ── Outputs ─────────────────────────────────────────────────────────────────
output apiUrl string = 'https://${apiApp.properties.configuration.ingress.fqdn}'
output frontendUrl string = 'https://${frontendApp.properties.configuration.ingress.fqdn}'
output postgresHost string = postgres.properties.fullyQualifiedDomainName

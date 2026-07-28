@description('Assessment Toolkit — Azure Container Apps deployment')
param location string = resourceGroup().location
param environmentName string = 'assessment-toolkit'
param postgresAdminPassword string

@secure()
param acrPassword string
param acrServer string
param acrUsername string

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
resource postgres 'Microsoft.DBforPostgreSQL/flexibleServers@2023-12-01-preview' = {
  name: '${environmentName}-pg'
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

resource postgresDb 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2023-12-01-preview' = {
  parent: postgres
  name: 'assessmentdb'
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
        image: '${acrServer}/assessment-toolkit/api:latest'
        resources: { cpu: json('0.5'), memory: '1Gi' }
        env: [
          { name: 'ASPNETCORE_ENVIRONMENT', value: 'Production' }
          { name: 'ConnectionStrings__Postgres', secretRef: 'postgres-conn' }
          { name: 'Api__PublicUrl', value: 'https://${environmentName}-api.${acaEnv.properties.defaultDomain}' }
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
        image: '${acrServer}/assessment-toolkit/worker:latest'
        resources: { cpu: json('0.5'), memory: '1Gi' }
        env: [
          { name: 'ASPNETCORE_ENVIRONMENT', value: 'Production' }
          { name: 'ConnectionStrings__Postgres', secretRef: 'postgres-conn' }
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
        image: '${acrServer}/assessment-toolkit/frontend:latest'
        resources: { cpu: json('0.25'), memory: '0.5Gi' }
        env: [{ name: 'VITE_API_URL', value: 'https://${apiApp.properties.configuration.ingress.fqdn}' }]
      }]
      scale: { minReplicas: 1, maxReplicas: 2 }
    }
  }
}

// ── Outputs ─────────────────────────────────────────────────────────────────
output apiUrl string = 'https://${apiApp.properties.configuration.ingress.fqdn}'
output frontendUrl string = 'https://${frontendApp.properties.configuration.ingress.fqdn}'
output postgresHost string = postgres.properties.fullyQualifiedDomainName

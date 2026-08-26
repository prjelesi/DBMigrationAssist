targetScope = 'subscription'

@minLength(1)
@maxLength(64)
param environmentName string

@minLength(1)
param location string

param sessionId string
param deployedBy string
param createdAt string
param deployerObjectId string

@secure()
param postgresAdminPassword string

param appAdminEmail string
@secure()
param appAdminPassword string
@secure()
param workerServiceToken string
param appAdminDisplayName string = 'Administrator'
param configureSecrets bool = false

param containerImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
param apiContainerImage string = containerImage
param workerContainerImage string = containerImage
param frontendContainerImage string = containerImage
param discoveryAgentContainerImage string = containerImage

var resourceGroupName = 'rg-dbmigratio-dev-1fa1'
var virtualNetworkName = 'vnet-dbmigratio-dev-1fa1'
var containerAppsEnvironmentName = 'cae-dbmigratio-dev-1fa1'
var apiContainerAppName = 'ca-api-dbmigratio-dev-1fa1'
var workerContainerAppName = 'ca-worker-dbmigratio-dev-1fa1'
var frontendContainerAppName = 'ca-web-dbmigratio-dev-1fa1'
var discoveryAgentContainerAppName = 'ca-agent-dbmigratio-dev-1fa1'
var containerRegistryName = 'crdbmigratiodev1fa1'
var postgresServerName = 'psql-dbmigratio-dev-1fa1'
var storageAccountName = 'stdbmigratiodev1fa1'
var keyVaultName = 'kv-dbmigratio-dev-1fa1'
var managedIdentityName = 'id-dbmigratio-dev-1fa1'
var postgresAdministratorLogin = 'assessmentadmin'
var applicationDatabaseName = 'assessmentdb'

var tags = {
  'app-onboard-skill': 'true'
  'app-onboard-session-id': sessionId
  'created-at': createdAt
  environment: environmentName
  'deployed-by': deployedBy
}

resource resourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

module network './modules/network.bicep' = {
  name: 'network'
  scope: resourceGroup
  params: {
    location: location
    tags: tags
    virtualNetworkName: virtualNetworkName
  }
}

module identity './modules/identity.bicep' = {
  name: 'identity'
  scope: resourceGroup
  params: {
    location: location
    tags: tags
    managedIdentityName: managedIdentityName
  }
}

module registry './modules/container-registry.bicep' = {
  name: 'container-registry'
  scope: resourceGroup
  params: {
    location: location
    tags: tags
    containerRegistryName: containerRegistryName
  }
}

module storage './modules/storage.bicep' = {
  name: 'storage'
  scope: resourceGroup
  params: {
    location: location
    tags: tags
    storageAccountName: storageAccountName
    containerAppsSubnetId: network.outputs.containerAppsSubnetId
  }
}

module keyVault './modules/key-vault.bicep' = {
  name: 'key-vault'
  scope: resourceGroup
  params: {
    location: location
    tags: tags
    keyVaultName: keyVaultName
  }
}

module containerAppsEnvironment './modules/container-apps-environment.bicep' = {
  name: 'container-apps-environment'
  scope: resourceGroup
  params: {
    location: location
    tags: tags
    containerAppsEnvironmentName: containerAppsEnvironmentName
    infrastructureSubnetId: network.outputs.containerAppsSubnetId
    storageAccountName: storageAccountName
    evidenceShareName: storage.outputs.evidenceShareName
    dataProtectionShareName: storage.outputs.dataProtectionShareName
    localAgentShareName: storage.outputs.localAgentShareName
  }
}

module postgres './modules/postgresql.bicep' = {
  name: 'postgresql'
  scope: resourceGroup
  params: {
    location: location
    tags: tags
    postgresServerName: postgresServerName
    administratorLogin: postgresAdministratorLogin
    administratorLoginPassword: postgresAdminPassword
    applicationDatabaseName: applicationDatabaseName
    delegatedSubnetResourceId: network.outputs.postgresSubnetId
    privateDnsZoneResourceId: network.outputs.postgresPrivateDnsZoneId
  }
}

module roleAssignments './modules/role-assignments.bicep' = {
  name: 'role-assignments'
  scope: resourceGroup
  params: {
    containerRegistryName: containerRegistryName
    keyVaultName: keyVaultName
    managedIdentityPrincipalId: identity.outputs.principalId
    deployerObjectId: deployerObjectId
  }
  dependsOn: [
    registry
    keyVault
  ]
}

module secrets './modules/secrets.bicep' = if (configureSecrets) {
  name: 'secrets'
  scope: resourceGroup
  params: {
    keyVaultName: keyVaultName
    postgresHost: postgres.outputs.fullyQualifiedDomainName
    postgresDatabaseName: applicationDatabaseName
    postgresAdministratorLogin: postgresAdministratorLogin
    postgresAdministratorPassword: postgresAdminPassword
    appAdminPassword: appAdminPassword
    workerServiceToken: workerServiceToken
  }
  dependsOn: [
    roleAssignments
  ]
}

module api './modules/api-container-app.bicep' = {
  name: 'api-container-app'
  scope: resourceGroup
  params: {
    location: location
    tags: tags
    containerAppName: apiContainerAppName
    containerAppsEnvironmentId: containerAppsEnvironment.outputs.id
    containerAppsEnvironmentDefaultDomain: containerAppsEnvironment.outputs.defaultDomain
    containerRegistryLoginServer: registry.outputs.loginServer
    managedIdentityId: identity.outputs.id
    keyVaultName: keyVaultName
    containerImage: apiContainerImage
    appAdminEmail: appAdminEmail
    appAdminDisplayName: appAdminDisplayName
  }
  dependsOn: [
    secrets
  ]
}

module worker './modules/worker-container-app.bicep' = {
  name: 'worker-container-app'
  scope: resourceGroup
  params: {
    location: location
    tags: tags
    containerAppName: workerContainerAppName
    containerAppsEnvironmentId: containerAppsEnvironment.outputs.id
    containerRegistryLoginServer: registry.outputs.loginServer
    managedIdentityId: identity.outputs.id
    keyVaultName: keyVaultName
    apiBaseUrl: api.outputs.url
    containerImage: workerContainerImage
  }
  dependsOn: [
    secrets
  ]
}

module discoveryAgent './modules/agent-container-app.bicep' = {
  name: 'discovery-agent-container-app'
  scope: resourceGroup
  params: {
    location: location
    tags: tags
    containerAppName: discoveryAgentContainerAppName
    containerAppsEnvironmentId: containerAppsEnvironment.outputs.id
    containerRegistryLoginServer: registry.outputs.loginServer
    managedIdentityId: identity.outputs.id
    containerImage: discoveryAgentContainerImage
  }
  dependsOn: [
    api
  ]
}

module frontend './modules/frontend-container-app.bicep' = {
  name: 'frontend-container-app'
  scope: resourceGroup
  params: {
    location: location
    tags: tags
    containerAppName: frontendContainerAppName
    containerAppsEnvironmentId: containerAppsEnvironment.outputs.id
    containerRegistryLoginServer: registry.outputs.loginServer
    managedIdentityId: identity.outputs.id
    apiBaseUrl: api.outputs.url
    containerImage: frontendContainerImage
  }
}

output resourceGroupName string = resourceGroup.name
output containerRegistryName string = containerRegistryName
output containerRegistryLoginServer string = registry.outputs.loginServer
output keyVaultName string = keyVaultName
output postgresHost string = postgres.outputs.fullyQualifiedDomainName
output apiUrl string = api.outputs.url
output frontendUrl string = frontend.outputs.url
output discoveryAgentId string = discoveryAgent.outputs.id

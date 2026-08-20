targetScope = 'subscription'

@description('Azure region for the database lab.')
param location string = 'eastus2'

@description('Resource group that contains the disposable database lab.')
param resourceGroupName string = 'rg-dbmlab-eastus2'

@description('Tags applied to every database-lab resource.')
param tags object = {
  project: 'dbmigration'
  environment: 'demo'
  workload: 'source-databases'
  lifecycle: 'disposable'
}

@description('Public SSH key for the Linux administrator account.')
param adminSshPublicKey string

@description('CIDR allowed to connect to TCP 22 on the two hosts.')
param adminSourceCidr string

@description('Shared synthetic administrator password for the containerized source databases.')
@minLength(12)
@secure()
param databaseAdminPassword string

@description('Oracle SYS, SYSTEM, and PDBADMIN bootstrap password.')
@minLength(12)
@maxLength(30)
@secure()
param oracleSysPassword string

@description('Linux administrator username.')
param adminUsername string = 'dbmlabadmin'

@description('Multi-engine VM size.')
param engineVmSize string = 'Standard_E4-2ads_v7'

@description('Oracle VM size.')
param oracleVmSize string = 'Standard_E2ads_v7'

resource databaseLabResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

module identity './modules/identity.bicep' = {
  scope: databaseLabResourceGroup
  params: {
    location: location
    tags: tags
    resourceToken: uniqueString(subscription().id, databaseLabResourceGroup.id)
    databaseAdminPassword: databaseAdminPassword
    oracleSysPassword: oracleSysPassword
  }
}

module network './modules/network.bicep' = {
  scope: databaseLabResourceGroup
  params: {
    location: location
    tags: tags
    adminSourceCidr: adminSourceCidr
  }
}

module compute './modules/compute.bicep' = {
  scope: databaseLabResourceGroup
  params: {
    location: location
    tags: tags
    adminUsername: adminUsername
    adminSshPublicKey: adminSshPublicKey
    engineVmSize: engineVmSize
    oracleVmSize: oracleVmSize
    engineNicId: network.outputs.engineNicId
    oracleNicId: network.outputs.oracleNicId
    bootstrapIdentityId: identity.outputs.identityId
    bootstrapIdentityClientId: identity.outputs.identityClientId
    keyVaultName: identity.outputs.keyVaultName
  }
}

output resourceGroupId string = databaseLabResourceGroup.id
output enginePrivateIp string = network.outputs.enginePrivateIp
output oraclePrivateIp string = network.outputs.oraclePrivateIp
output enginePublicIp string = network.outputs.enginePublicIp
output oraclePublicIp string = network.outputs.oraclePublicIp
output engineVmId string = compute.outputs.engineVmId
output oracleVmId string = compute.outputs.oracleVmId

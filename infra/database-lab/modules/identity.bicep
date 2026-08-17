@description('Azure region for identity and Key Vault resources.')
param location string

@description('Tags applied to identity and Key Vault resources.')
param tags object

@description('Deterministic token used to make the Key Vault name globally unique.')
param resourceToken string

@description('Shared synthetic administrator password for the containerized databases.')
@minLength(12)
@secure()
param databaseAdminPassword string

@description('Oracle SYS, SYSTEM, and PDBADMIN bootstrap password.')
@minLength(12)
@secure()
param oracleSysPassword string

var keyVaultName = take('kv-dbmlab-${resourceToken}', 24)

resource bootstrapIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: 'id-dbmlab'
  location: location
  tags: tags
}

resource keyVault 'Microsoft.KeyVault/vaults@2024-11-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    tenantId: tenant().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enablePurgeProtection: true
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Enabled'
  }
}

resource databasePasswordSecret 'Microsoft.KeyVault/vaults/secrets@2024-11-01' = {
  parent: keyVault
  name: 'database-admin-password'
  properties: {
    value: databaseAdminPassword
    contentType: 'database bootstrap credential'
  }
}

resource oraclePasswordSecret 'Microsoft.KeyVault/vaults/secrets@2024-11-01' = {
  parent: keyVault
  name: 'oracle-sys-password'
  properties: {
    value: oracleSysPassword
    contentType: 'Oracle SYS bootstrap credential'
  }
}

resource keyVaultSecretsUserRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: '4633458b-17de-408a-b874-0445c86b69e6'
}

resource bootstrapSecretsRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, bootstrapIdentity.id, keyVaultSecretsUserRole.id)
  scope: keyVault
  properties: {
    principalId: bootstrapIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: keyVaultSecretsUserRole.id
  }
}

output identityId string = bootstrapIdentity.id
output identityClientId string = bootstrapIdentity.properties.clientId
output keyVaultName string = keyVault.name

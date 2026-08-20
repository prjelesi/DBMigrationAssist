param keyVaultName string
param postgresHost string
param postgresDatabaseName string
param postgresAdministratorLogin string
@secure()
param postgresAdministratorPassword string
@secure()
param appAdminPassword string
@secure()
param workerServiceToken string
var postgresSslMode = 'Require'

resource keyVault 'Microsoft.KeyVault/vaults@2026-02-01' existing = {
  name: keyVaultName
}

resource postgresAdminPassword 'Microsoft.KeyVault/vaults/secrets@2026-02-01' = {
  parent: keyVault
  name: 'postgres-admin-password'
  properties: {
    value: postgresAdministratorPassword
  }
}

resource postgresConnectionString 'Microsoft.KeyVault/vaults/secrets@2026-02-01' = {
  parent: keyVault
  name: 'postgres-connection-string'
  properties: {
    value: join([
      'Host=${postgresHost};Port=5432;Database=${postgresDatabaseName};Username=${postgresAdministratorLogin};'
      'Password'
      '=${postgresAdministratorPassword};SSL Mode=${postgresSslMode};Trust Server Certificate=false'
    ], '')
  }
}

resource appAdminPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2026-02-01' = {
  parent: keyVault
  name: 'app-admin-password'
  properties: {
    value: appAdminPassword
  }
}

resource workerServiceTokenSecret 'Microsoft.KeyVault/vaults/secrets@2026-02-01' = {
  parent: keyVault
  name: 'worker-service-token'
  properties: {
    value: workerServiceToken
  }
}

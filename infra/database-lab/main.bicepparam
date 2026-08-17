using './main.bicep'

param location = 'eastus2'
param resourceGroupName = 'rg-dbmlab-eastus2'
param adminUsername = 'dbmlabadmin'
param adminSourceCidr = '203.0.113.10/32'
param adminSshPublicKey = readEnvironmentVariable('DBMLAB_ADMIN_SSH_PUBLIC_KEY')
param databaseAdminPassword = readEnvironmentVariable('DBMLAB_DATABASE_ADMIN_PASSWORD')
param oracleSysPassword = readEnvironmentVariable('DBMLAB_ORACLE_SYS_PASSWORD')

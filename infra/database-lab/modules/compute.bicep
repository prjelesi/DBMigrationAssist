@description('Azure region for compute resources.')
param location string

@description('Tags applied to compute resources.')
param tags object

@description('Linux administrator username.')
param adminUsername string

@description('Public SSH key for the Linux administrator account.')
param adminSshPublicKey string

@description('Multi-engine VM size.')
param engineVmSize string

@description('Oracle VM size.')
param oracleVmSize string

@description('Resource ID of the multi-engine network interface.')
param engineNicId string

@description('Resource ID of the Oracle network interface.')
param oracleNicId string

@description('Resource ID of the bootstrap user-assigned identity.')
param bootstrapIdentityId string

@description('Client ID of the bootstrap user-assigned identity.')
param bootstrapIdentityClientId string

@description('Name of the Key Vault containing bootstrap credentials.')
param keyVaultName string

var engineCloudInit = replace(replace(replace(
  loadTextContent('../bootstrap/engine-cloud-init.yml'),
  '__ADMIN_USERNAME__',
  adminUsername
), '__KEY_VAULT_NAME__', keyVaultName), '__IDENTITY_CLIENT_ID__', bootstrapIdentityClientId)

var oracleCloudInit = replace(replace(replace(
  loadTextContent('../bootstrap/oracle-cloud-init.yml'),
  '__ADMIN_USERNAME__',
  adminUsername
), '__KEY_VAULT_NAME__', keyVaultName), '__IDENTITY_CLIENT_ID__', bootstrapIdentityClientId)

resource engineDataDisk 'Microsoft.Compute/disks@2025-01-02' = {
  name: 'disk-dbmlab-engine-data'
  location: location
  tags: tags
  sku: {
    name: 'StandardSSD_LRS'
  }
  properties: {
    diskSizeGB: 256
    creationData: {
      createOption: 'Empty'
    }
    networkAccessPolicy: 'DenyAll'
    publicNetworkAccess: 'Disabled'
  }
}

resource oracleDataDisk 'Microsoft.Compute/disks@2025-01-02' = {
  name: 'disk-dbmlab-oracle-data'
  location: location
  tags: tags
  sku: {
    name: 'StandardSSD_LRS'
  }
  properties: {
    diskSizeGB: 128
    creationData: {
      createOption: 'Empty'
    }
    networkAccessPolicy: 'DenyAll'
    publicNetworkAccess: 'Disabled'
  }
}

resource engineVm 'Microsoft.Compute/virtualMachines@2024-11-01' = {
  name: 'vm-dbmlab-engine'
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${bootstrapIdentityId}': {}
    }
  }
  properties: {
    hardwareProfile: {
      vmSize: engineVmSize
    }
    securityProfile: {
      securityType: 'TrustedLaunch'
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
    }
    osProfile: {
      computerName: 'dbmlab-engine'
      adminUsername: adminUsername
      customData: base64(engineCloudInit)
      linuxConfiguration: {
        disablePasswordAuthentication: true
        patchSettings: {
          patchMode: 'AutomaticByPlatform'
          assessmentMode: 'AutomaticByPlatform'
        }
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: adminSshPublicKey
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        diskSizeGB: 64
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
      dataDisks: [
        {
          lun: 0
          createOption: 'Attach'
          managedDisk: {
            id: engineDataDisk.id
          }
        }
      ]
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: engineNicId
          properties: {
            primary: true
          }
        }
      ]
    }
  }
}

resource oracleVm 'Microsoft.Compute/virtualMachines@2024-11-01' = {
  name: 'vm-dbmlab-oracle'
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${bootstrapIdentityId}': {}
    }
  }
  properties: {
    hardwareProfile: {
      vmSize: oracleVmSize
    }
    osProfile: {
      computerName: 'dbmlab-oracle'
      adminUsername: adminUsername
      customData: base64(oracleCloudInit)
      linuxConfiguration: {
        disablePasswordAuthentication: true
        patchSettings: {
          patchMode: 'ImageDefault'
        }
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: adminSshPublicKey
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Oracle'
        offer: 'Oracle-Linux'
        sku: 'ol810-lvm-gen2'
        version: '8.10.9'
      }
      osDisk: {
        createOption: 'FromImage'
        diskSizeGB: 64
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
      dataDisks: [
        {
          lun: 0
          createOption: 'Attach'
          managedDisk: {
            id: oracleDataDisk.id
          }
        }
      ]
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: oracleNicId
          properties: {
            primary: true
          }
        }
      ]
    }
  }
}

output engineVmId string = engineVm.id
output oracleVmId string = oracleVm.id

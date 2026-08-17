@description('Azure region for network resources.')
param location string

@description('Tags applied to network resources.')
param tags object

@description('CIDR allowed to connect to TCP 22.')
param adminSourceCidr string

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2024-07-01' = {
  name: 'nsg-dbmlab'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowSshFromAdmin'
        properties: {
          priority: 100
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: adminSourceCidr
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
      {
        name: 'AllowDatabasePortsFromVnet'
        properties: {
          priority: 200
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRanges: [
            '1433'
            '1521'
            '3306'
            '5432'
            '9042'
            '27017'
          ]
        }
      }
      {
        name: 'DenyAllOtherInbound'
        properties: {
          priority: 4096
          protocol: '*'
          access: 'Deny'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-07-01' = {
  name: 'vnet-dbmlab'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.40.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'snet-databases'
        properties: {
          addressPrefix: '10.40.1.0/24'
          networkSecurityGroup: {
            id: networkSecurityGroup.id
          }
        }
      }
    ]
  }
}

resource enginePublicIp 'Microsoft.Network/publicIPAddresses@2024-07-01' = {
  name: 'pip-dbmlab-engine'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

resource oraclePublicIp 'Microsoft.Network/publicIPAddresses@2024-07-01' = {
  name: 'pip-dbmlab-oracle'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

resource engineNic 'Microsoft.Network/networkInterfaces@2024-07-01' = {
  name: 'nic-dbmlab-engine'
  location: location
  tags: tags
  properties: {
    enableAcceleratedNetworking: true
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAddress: '10.40.1.10'
          privateIPAllocationMethod: 'Static'
          privateIPAddressVersion: 'IPv4'
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetwork.name, 'snet-databases')
          }
          publicIPAddress: {
            id: enginePublicIp.id
          }
        }
      }
    ]
  }
}

resource oracleNic 'Microsoft.Network/networkInterfaces@2024-07-01' = {
  name: 'nic-dbmlab-oracle'
  location: location
  tags: tags
  properties: {
    enableAcceleratedNetworking: true
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAddress: '10.40.1.20'
          privateIPAllocationMethod: 'Static'
          privateIPAddressVersion: 'IPv4'
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetwork.name, 'snet-databases')
          }
          publicIPAddress: {
            id: oraclePublicIp.id
          }
        }
      }
    ]
  }
}

output engineNicId string = engineNic.id
output oracleNicId string = oracleNic.id
output enginePrivateIp string = '10.40.1.10'
output oraclePrivateIp string = '10.40.1.20'
output enginePublicIp string = enginePublicIp.properties.ipAddress
output oraclePublicIp string = oraclePublicIp.properties.ipAddress

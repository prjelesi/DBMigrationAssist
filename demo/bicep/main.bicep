@description('Azure region for all demo resources')
param location string = resourceGroup().location

@description('Admin username for the demo VM')
param adminUsername string = 'demoadmin'

@description('Admin password for the demo VM')
@secure()
param adminPassword string

@description('Your public IP address for NSG access (run: curl ifconfig.me)')
param allowedSourceIp string = '*'

@description('VM size')
param vmSize string = 'Standard_D4s_v3'

var vmName = 'vm-demo-dbs'
var nicName = 'nic-demo-dbs'
var nsgName = 'nsg-demo-dbs'
var vnetName = 'vnet-demo'
var publicIpName = 'pip-demo-dbs'
var subnetName = 'subnet-demo'

// ── Public IP ─────────────────────────────────────────────────────────────────
resource publicIp 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: publicIpName
  location: location
  sku: { name: 'Standard' }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: { domainNameLabel: 'dbmigration-demo-${uniqueString(resourceGroup().id)}' }
  }
}

// ── NSG — open each DB port + SSH from your IP only ──────────────────────────
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'allow-ssh'
        properties: {
          priority: 100
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: allowedSourceIp
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
      {
        name: 'allow-sqlserver'
        properties: {
          priority: 200
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: allowedSourceIp
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '1433'
        }
      }
      {
        name: 'allow-postgresql'
        properties: {
          priority: 210
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: allowedSourceIp
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '5432'
        }
      }
      {
        name: 'allow-mysql'
        properties: {
          priority: 220
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: allowedSourceIp
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '3306'
        }
      }
      {
        name: 'allow-mariadb'
        properties: {
          priority: 230
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: allowedSourceIp
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '3307'
        }
      }
      {
        name: 'allow-mongodb'
        properties: {
          priority: 240
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: allowedSourceIp
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '27017'
        }
      }
      {
        name: 'allow-cassandra'
        properties: {
          priority: 250
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: allowedSourceIp
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '9042'
        }
      }
      {
        name: 'allow-assessment-api'
        properties: {
          priority: 300
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: allowedSourceIp
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '8000'
        }
      }
    ]
  }
}

// ── VNet & Subnet ─────────────────────────────────────────────────────────────
resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: { addressPrefixes: ['10.0.0.0/16'] }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: '10.0.1.0/24'
          networkSecurityGroup: { id: nsg.id }
        }
      }
    ]
  }
}

// ── NIC ───────────────────────────────────────────────────────────────────────
resource nic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: nicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: { id: publicIp.id }
          subnet: { id: '${vnet.id}/subnets/${subnetName}' }
        }
      }
    ]
  }
}

// ── VM with cloud-init ────────────────────────────────────────────────────────
resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: { vmSize: vmSize }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
      customData: base64(loadTextContent('cloud-init.yml'))
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        diskSizeGB: 128
        managedDisk: { storageAccountType: 'Premium_LRS' }
      }
    }
    networkProfile: {
      networkInterfaces: [{ id: nic.id }]
    }
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────
output vmPublicIp string = publicIp.properties.ipAddress
output vmFqdn string = publicIp.properties.dnsSettings.fqdn
output sshCommand string = 'ssh ${adminUsername}@${publicIp.properties.dnsSettings.fqdn}'
output connectionStrings object = {
  sqlserver:  'Server=${publicIp.properties.dnsSettings.fqdn},1433;Database=DemoDB;User=sa;Password=Demo@Password123'
  postgresql: 'Host=${publicIp.properties.dnsSettings.fqdn};Port=5432;Database=demodb;Username=demouser;Password=Demo@Password123'
  mysql:      'Server=${publicIp.properties.dnsSettings.fqdn};Port=3306;Database=demodb;Uid=demouser;Pwd=Demo@Password123'
  mariadb:    'Server=${publicIp.properties.dnsSettings.fqdn};Port=3307;Database=demodb;Uid=demouser;Pwd=Demo@Password123'
  mongodb:    'mongodb://demouser:Demo%40Password123@${publicIp.properties.dnsSettings.fqdn}:27017/demodb'
  cassandra:  '${publicIp.properties.dnsSettings.fqdn}:9042 (keyspace: demodb, user: demouser)'
}

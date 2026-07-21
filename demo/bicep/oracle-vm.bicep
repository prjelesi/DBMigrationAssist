@description('Azure region')
param location string = resourceGroup().location

@description('VM admin username')
param adminUsername string = 'demoadmin'

@description('VM admin password')
@secure()
param adminPassword string

@description('Your public IP for NSG access')
param allowedSourceIp string = '*'

@description('VM size — Oracle needs at least 2 vCPUs and 8GB RAM')
param vmSize string = 'Standard_D4s_v3'

@description('Oracle SYS password (set during install)')
@secure()
param oracleSysPassword string = 'OracleDemo@2026!'

var vmName = 'vm-demo-oracle'
var nicName = 'nic-demo-oracle'
var nsgName = 'nsg-demo-oracle'
var vnetName = 'vnet-demo-oracle'
var publicIpName = 'pip-demo-oracle'
var subnetName = 'subnet-demo-oracle'

resource publicIp 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: publicIpName
  location: location
  sku: { name: 'Standard' }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: { domainNameLabel: 'ora-demo-${uniqueString(resourceGroup().id)}' }
  }
}

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
        name: 'allow-oracle-listener'
        properties: {
          priority: 200
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: allowedSourceIp
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '1521'
        }
      }
      {
        name: 'allow-oracle-em-express'
        properties: {
          priority: 210
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: allowedSourceIp
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '5500'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: { addressPrefixes: ['10.1.0.0/16'] }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: '10.1.1.0/24'
          networkSecurityGroup: { id: nsg.id }
        }
      }
    ]
  }
}

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

resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: { vmSize: vmSize }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
      customData: base64(replace(
        loadTextContent('cloud-init-oracle.yml'),
        '{{ORACLE_SYS_PASSWORD}}',
        oracleSysPassword
      ))
    }
    storageProfile: {
      imageReference: {
        // Oracle Linux 9.3 — best supported OS for Oracle Database 23ai Free
        publisher: 'Oracle'
        offer: 'Oracle-Linux'
        sku: 'ol93-gen2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        // Oracle recommends 50GB minimum; we use 128GB for demo data headroom
        diskSizeGB: 128
        managedDisk: { storageAccountType: 'Premium_LRS' }
      }
    }
    networkProfile: {
      networkInterfaces: [{ id: nic.id }]
    }
  }
}

output vmPublicIp string = publicIp.properties.ipAddress
output vmFqdn string = publicIp.properties.dnsSettings.fqdn
output sshCommand string = 'ssh ${adminUsername}@${publicIp.properties.dnsSettings.fqdn}'
output oracleConnectionString string = '(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${publicIp.properties.dnsSettings.fqdn})(PORT=1521))(CONNECT_DATA=(SERVICE_NAME=FREEPDB1)))'
output sqlplusCommand string = 'sqlplus system/${oracleSysPassword}@//${publicIp.properties.dnsSettings.fqdn}:1521/FREEPDB1'
output emExpressUrl string = 'https://${publicIp.properties.dnsSettings.fqdn}:5500/em'
output oracleVersion string = 'Oracle XE 21c (free dev edition — functionally equivalent to 19c/21c Enterprise for factory script purposes)'
output note string = 'Oracle XE 21c install takes ~15-20 minutes. Monitor: ssh then sudo tail -f /var/log/oracle-install.log'

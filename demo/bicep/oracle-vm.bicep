@description('Azure region')
param location string = resourceGroup().location

@description('VM admin username')
param adminUsername string = 'demoadmin'

@description('VM admin password')
@secure()
param adminPassword string

@description('Your public IP for NSG access')
param allowedSourceIp string = '*'

@description('VM size — Oracle XE 21c needs at least 2 vCPUs and 8GB RAM')
param vmSize string = 'Standard_D4s_v3'

@description('Oracle SYS/SYSTEM/PDBADMIN password')
@secure()
param oracleSysPassword string

@description('Name of the existing VNet to join (created by main.bicep)')
param existingVnetName string = 'vnet-demo'

@description('Name of the existing subnet inside that VNet')
param existingSubnetName string = 'subnet-demo'

var vmName       = 'vm-demo-oracle'
var nicName      = 'nic-demo-oracle'
var nsgName      = 'nsg-demo-oracle'
var publicIpName = 'pip-demo-oracle'

// ── Public IP ─────────────────────────────────────────────────────────────────
resource publicIp 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: publicIpName
  location: location
  sku: { name: 'Standard' }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: { domainNameLabel: 'ora-demo-${uniqueString(resourceGroup().id)}' }
  }
}

// ── NIC-level NSG (Oracle-specific ports — applied to NIC, not subnet) ────────
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

// ── Reference the existing VNet/subnet (created by main.bicep) ────────────────
resource existingVnet 'Microsoft.Network/virtualNetworks@2023-09-01' existing = {
  name: existingVnetName
}

resource existingSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' existing = {
  parent: existingVnet
  name: existingSubnetName
}

// ── NIC — placed in existing subnet, NSG applied at NIC level ─────────────────
resource nic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: nicName
  location: location
  properties: {
    networkSecurityGroup: { id: nsg.id }
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: { id: publicIp.id }
          subnet: { id: existingSubnet.id }
        }
      }
    ]
  }
}

// ── Oracle VM on Oracle Linux 9 ───────────────────────────────────────────────
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
        publisher: 'Oracle'
        offer: 'Oracle-Linux'
        sku: 'ol97-lvm-gen2'
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
output vmPrivateIp string = nic.properties.ipConfigurations[0].properties.privateIPAddress
output vnetName string = existingVnetName
output subnetName string = existingSubnetName
output sshCommand string = 'ssh ${adminUsername}@${publicIp.properties.dnsSettings.fqdn}'
output sqlplusPublic string = 'sqlplus demouser/Demo@Password123@//${publicIp.properties.dnsSettings.fqdn}:1521/XEPDB1'
output sqlplusPrivate string = 'sqlplus demouser/Demo@Password123@//${nic.properties.ipConfigurations[0].properties.privateIPAddress}:1521/XEPDB1'
output emExpressUrl string = 'https://${publicIp.properties.dnsSettings.fqdn}:5500/em'
output oracleVersion string = 'Oracle XE 21c — free dev edition on Oracle Linux 9'
output note string = 'Oracle install takes ~15-20 min. Monitor: ssh then: sudo tail -f /var/log/oracle-install.log'

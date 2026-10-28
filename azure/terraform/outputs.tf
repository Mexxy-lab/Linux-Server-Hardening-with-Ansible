output "resource_group_name" {
  description = "Resource group containing the lab resources."
  value       = azurerm_resource_group.lab.name
}

output "vm_name" {
  description = "Name of the Ubuntu virtual machine."
  value       = azurerm_linux_virtual_machine.lab.name
}

output "public_ip" {
  description = "Public IPv4 address used by Ansible and SSH."
  value       = azurerm_public_ip.lab.ip_address
}

output "private_ip" {
  description = "Private IPv4 address assigned to the VM."
  value       = azurerm_network_interface.lab.private_ip_address
}

output "trusted_ssh_cidr" {
  description = "CIDR permitted to access SSH through the NSG."
  value       = var.trusted_ssh_cidr
}

output "ssh_command" {
  description = "Example command for the initial Azure administrator."
  value       = "ssh -i ~/.ssh/linux_hardening_ed25519 azureuser@${azurerm_public_ip.lab.ip_address}"
}

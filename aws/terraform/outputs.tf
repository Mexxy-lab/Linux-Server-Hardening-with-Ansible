# Display the EC2 public IP for SSH and Ansible connectivity.
output "instance_public_ip" {
  description = "Public IPv4 address of the Ubuntu server."
  value       = aws_instance.linux.public_ip
}

# Display the private address used inside the VPC.
output "instance_private_ip" {
  description = "Private IPv4 address of the Ubuntu server."
  value       = aws_instance.linux.private_ip
}

# Display the instance ID for AWS CLI operations.
output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.linux.id
}

# Make the security boundary visible after deployment.
output "trusted_ssh_cidr" {
  description = "Public IPv4 CIDR permitted to connect over SSH."
  value       = var.trusted_ssh_cidr
}

# Show the command to connect using the local private key.
output "ssh_command" {
  description = "Example SSH command for the Ubuntu instance."
  value       = "ssh -i ~/.ssh/linux_hardening_ed25519 ubuntu@${aws_instance.linux.public_ip}"
}

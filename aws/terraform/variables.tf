variable "aws_region" {
  description = "AWS region where the Linux hardening lab will be deployed."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix used to identify resources belonging to this project."
  type        = string
  default     = "linux-hardening"
}

variable "instance_type" {
  description = "EC2 instance type. Check current pricing and eligibility before deployment."
  type        = string
  default     = "t3.micro"
}

variable "trusted_ssh_cidr" {
  description = "Trusted public IPv4 CIDR permitted to connect over SSH."
  type        = string

  # Require a narrowly scoped IPv4 CIDR instead of an unrestricted rule.
  validation {
    condition     = can(cidrnetmask(var.trusted_ssh_cidr)) && can(regex("/32$", var.trusted_ssh_cidr))
    error_message = "Use one trusted IPv4 address in /32 format, such as 203.0.113.10/32."
  }
}

variable "public_key_path" {
  description = "Path to the SSH public key on the machine running Terraform."
  type        = string
  default     = "~/.ssh/linux_hardening_ed25519.pub"
}

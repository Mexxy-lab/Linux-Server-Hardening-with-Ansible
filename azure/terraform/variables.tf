variable "subscription_id" {
  description = "Azure subscription ID used for this deployment."
  type        = string
}

variable "location" {
  description = "Azure region for the Linux hardening lab."
  type        = string
  default     = "eastus"
}

variable "project_name" {
  description = "Prefix used to name this project's Azure resources."
  type        = string
  default     = "linux-hardening"
}

variable "vm_size" {
  description = "Azure VM size; verify availability, quota, and pricing."
  type        = string
  default     = "Standard_B1s"
}

variable "trusted_ssh_cidr" {
  description = "Trusted public IPv4 address allowed to connect over SSH."
  type        = string

  # Restrict SSH to one public IPv4 address instead of the entire internet.
  validation {
    condition = (
      can(cidrnetmask(var.trusted_ssh_cidr)) &&
      can(regex("/32$", var.trusted_ssh_cidr))
    )
    error_message = "Use a single trusted IPv4 address in /32 format."
  }
}

variable "public_key_path" {
  description = "Path to the SSH public key used for VM access."
  type        = string
  default     = "~/.ssh/linux_hardening_ed25519.pub"
}

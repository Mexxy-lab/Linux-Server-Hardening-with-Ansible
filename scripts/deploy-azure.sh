#!/usr/bin/env bash

# Stop if a command fails, an unset variable is used, or a pipeline fails.
set -Eeuo pipefail

# Resolve paths relative to the repository, not the current working directory.
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERRAFORM_DIR="${PROJECT_ROOT}/azure/terraform"
PUBLIC_KEY="${HOME}/.ssh/linux_hardening_ed25519.pub"
PRIVATE_KEY="${HOME}/.ssh/linux_hardening_ed25519"

# Keep generated inventory temporary and remove it when the script exits.
INVENTORY_FILE="$(mktemp)"
trap 'rm -f "${INVENTORY_FILE}"' EXIT

cd "${PROJECT_ROOT}"

echo "=== Preflight checks ==="

# Confirm the tools needed for Azure provisioning and Ansible are installed.
for command in terraform ansible ansible-playbook az ssh; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "ERROR: Required command not found: ${command}" >&2
    exit 1
  fi
done

# Require the existing SSH key pair used by the AWS and local lab.
if [[ ! -f "${PUBLIC_KEY}" || ! -f "${PRIVATE_KEY}" ]]; then
  echo "ERROR: SSH key pair not found under ${HOME}/.ssh." >&2
  exit 1
fi

# Confirm that the Ansible Vault file exists without displaying its contents.
if [[ ! -f "${PROJECT_ROOT}/ansible/group_vars/vault.yml" ]]; then
  echo "ERROR: Ansible Vault file is missing." >&2
  exit 1
fi

# Confirm Azure CLI is logged in and identify the active subscription.
if ! az account show >/dev/null 2>&1; then
  echo "ERROR: Azure CLI is not logged in. Run: az login" >&2
  exit 1
fi

echo "Active Azure subscription:"
az account show --query '{name:name,id:id}' --output table

echo
echo "=== Ansible preflight checks ==="

# Validate hardening playbook syntax and the Vault password before provisioning.
ansible-playbook \
  -i ansible/inventories/vagrant/hosts.yml \
  ansible/playbooks/harden.yml \
  --syntax-check \
  --ask-vault-pass

# Validate the read-only verification playbook.
ansible-playbook \
  -i ansible/inventories/vagrant/hosts.yml \
  ansible/playbooks/validate.yml \
  --syntax-check

echo
echo "=== Terraform initialization and validation ==="

# Initialize the Azure provider and validate the configuration.
terraform -chdir="${TERRAFORM_DIR}" init
terraform -chdir="${TERRAFORM_DIR}" validate

echo
echo "=== Review the Azure deployment plan ==="

# Show planned resource changes without creating anything yet.
terraform -chdir="${TERRAFORM_DIR}" plan

echo
read -r -p "Type APPLY to create the Azure resources: " APPROVAL

# Require explicit approval before provisioning potentially billable resources.
if [[ "${APPROVAL}" != "APPLY" ]]; then
  echo "Deployment cancelled before resource creation."
  exit 0
fi

# Apply the reviewed Terraform plan; Terraform will request confirmation again.
terraform -chdir="${TERRAFORM_DIR}" apply

echo
echo "=== Retrieve the VM public IP ==="

# Read the VM address from Terraform after a successful apply.
PUBLIC_IP="$(terraform -chdir="${TERRAFORM_DIR}" output -raw public_ip)"

if [[ -z "${PUBLIC_IP}" ]]; then
  echo "ERROR: Terraform did not return a public IP." >&2
  exit 1
fi

echo "Azure VM public IP: ${PUBLIC_IP}"

echo
echo "=== Generate temporary Ansible inventory ==="

# Use Azure's initial account for the first connection.
# accept-new trusts the host key on first contact and remembers it for this host.
cat > "${INVENTORY_FILE}" <<INVENTORY
[linux_servers]
azure-linux ansible_host=${PUBLIC_IP} ansible_user=azureuser ansible_python_interpreter=/usr/bin/python3 ansible_ssh_private_key_file=${PRIVATE_KEY} ansible_ssh_common_args='-o StrictHostKeyChecking=accept-new'
INVENTORY

echo
echo "=== Wait for SSH connectivity ==="

# Wait for the new Ubuntu VM to become reachable before running configuration.
ansible -i "${INVENTORY_FILE}" linux_servers \
  -m ansible.builtin.wait_for_connection \
  -a "timeout=600" \
  -o

echo
echo "=== Apply the shared Linux hardening role ==="

# Re-enter the Vault password to decrypt the administrator password hash.
ansible-playbook \
  -i "${INVENTORY_FILE}" \
  ansible/playbooks/harden.yml \
  --ask-vault-pass

echo
echo "=== Validate the hardened VM ==="

# Run the read-only checks against the Azure VM.
ansible-playbook \
  -i "${INVENTORY_FILE}" \
  ansible/playbooks/validate.yml

echo
echo "Azure deployment and validation completed successfully."
echo "VM public IP: ${PUBLIC_IP}"
echo "Initial SSH command: ssh -i ${PRIVATE_KEY} azureuser@${PUBLIC_IP}"
echo "Dedicated admin account created by Ansible: linuxadmin"
echo "Temporary inventory will be removed when this script exits."
echo
echo "Next: verify linuxadmin SSH access and rerun hardening to test idempotency."

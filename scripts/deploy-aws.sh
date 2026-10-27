#!/usr/bin/env bash

# Stop on errors, unset variables, and failures inside pipelines.
set -Eeuo pipefail

# Resolve the project root so the script works from any directory.
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERRAFORM_DIR="${PROJECT_ROOT}/aws/terraform"
PUBLIC_KEY="${HOME}/.ssh/linux_hardening_ed25519.pub"
PRIVATE_KEY="${HOME}/.ssh/linux_hardening_ed25519"

# Temporary inventory is removed automatically when the script exits.
INVENTORY_FILE="$(mktemp)"
trap 'rm -f "${INVENTORY_FILE}"' EXIT

cd "${PROJECT_ROOT}"

echo "=== Preflight checks ==="

# Ensure Terraform, Ansible, AWS CLI, and SSH key files are available.
for command in terraform ansible ansible-playbook aws ssh; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "ERROR: Required command not found: ${command}" >&2
    exit 1
  fi
done

if [[ ! -f "${PUBLIC_KEY}" || ! -f "${PRIVATE_KEY}" ]]; then
  echo "ERROR: Expected SSH key pair was not found in ${HOME}/.ssh." >&2
  exit 1
fi

if [[ ! -f "${PROJECT_ROOT}/ansible/group_vars/vault.yml" ]]; then
  echo "ERROR: Ansible Vault file is missing." >&2
  exit 1
fi

# Verify AWS credentials before attempting Terraform operations.
aws sts get-caller-identity >/dev/null

echo "=== Ansible preflight checks ==="

# Verify the hardening playbook parses and the Vault password is accepted.
# This prompts for the Vault password before any AWS resources are created.
ansible-playbook \
  -i ansible/inventories/vagrant/hosts.yml \
  ansible/playbooks/harden.yml \
  --syntax-check \
  --ask-vault-pass

# Validate the read-only playbook syntax as well.
ansible-playbook \
  -i ansible/inventories/vagrant/hosts.yml \
  ansible/playbooks/validate.yml \
  --syntax-check

echo "Preflight checks passed."

echo "=== Terraform initialization and validation ==="

# Initialize the provider and validate the infrastructure configuration.
terraform -chdir="${TERRAFORM_DIR}" init
terraform -chdir="${TERRAFORM_DIR}" validate

echo "=== Review infrastructure plan ==="

# Show the proposed changes before creating AWS resources.
terraform -chdir="${TERRAFORM_DIR}" plan

echo
echo "Review the plan above. Terraform will ask for confirmation before creating resources."
read -r -p "Continue to Terraform apply? Type APPLY to proceed: " APPROVAL

if [[ "${APPROVAL}" != "APPLY" ]]; then
  echo "Deployment cancelled before infrastructure creation."
  exit 0
fi

# Terraform asks for its own confirmation unless -auto-approve is used.
terraform -chdir="${TERRAFORM_DIR}" apply

echo "=== Retrieve the EC2 address ==="

# Read the public IP from Terraform outputs after successful provisioning.
PUBLIC_IP="$(terraform -chdir="${TERRAFORM_DIR}" output -raw instance_public_ip)"

if [[ -z "${PUBLIC_IP}" ]]; then
  echo "ERROR: Terraform did not return an instance public IP." >&2
  exit 1
fi

echo "EC2 public IP: ${PUBLIC_IP}"

echo "=== Generate temporary Ansible inventory ==="

# Use Ubuntu's default cloud account for the initial connection.
# accept-new trusts a previously unknown host key on first connection.
# The inventory itself is temporary and is not committed to Git.
cat > "${INVENTORY_FILE}" <<INVENTORY
[linux_servers]
aws-linux ansible_host=${PUBLIC_IP} ansible_user=ubuntu ansible_python_interpreter=/usr/bin/python3 ansible_ssh_private_key_file=${PRIVATE_KEY} ansible_ssh_common_args='-o StrictHostKeyChecking=accept-new'
INVENTORY

echo "=== Wait for SSH connectivity ==="

# Wait until the newly created server is reachable over SSH.
ansible -i "${INVENTORY_FILE}" linux_servers \
  -m ansible.builtin.wait_for_connection \
  -a "timeout=600" \
  -o

echo "=== Apply Linux hardening ==="

# Prompt for the Ansible Vault password without putting it in the command line.
ansible-playbook \
  -i "${INVENTORY_FILE}" \
  ansible/playbooks/harden.yml \
  --ask-vault-pass

echo "=== Validate the hardening baseline ==="

# Run the existing read-only validation playbook.
ansible-playbook \
  -i "${INVENTORY_FILE}" \
  ansible/playbooks/validate.yml

echo
echo "Deployment and validation completed successfully."
echo "EC2 public IP: ${PUBLIC_IP}"
echo "SSH command: ssh -i ${PRIVATE_KEY} ubuntu@${PUBLIC_IP}"
echo
echo "The Ansible inventory was temporary and has been removed."
echo "Run the hardening playbook a second time to verify idempotency."

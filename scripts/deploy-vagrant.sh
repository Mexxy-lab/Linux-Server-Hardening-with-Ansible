#!/usr/bin/env bash
# Automate the local Linux server hardening deployment using Vagrant and Ansible.
# The Ansible Vault password is requested once and reused for the entire run.

set -Eeuo pipefail

# Resolve the repository root whether this script lives at the root or in scripts/.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -d "${SCRIPT_DIR}/vagrant" && -d "${SCRIPT_DIR}/ansible" ]]; then
  PROJECT_ROOT="${SCRIPT_DIR}"
elif [[ -d "${SCRIPT_DIR}/../vagrant" && -d "${SCRIPT_DIR}/../ansible" ]]; then
  PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
else
  echo "ERROR: Could not locate the project root containing vagrant/ and ansible/." >&2
  exit 1
fi

# Define the project paths in one place so they are easy to maintain.
VAGRANT_DIR="${PROJECT_ROOT}/vagrant"
INVENTORY="${PROJECT_ROOT}/ansible/inventories/vagrant/hosts.yml"
HARDEN_PLAYBOOK="${PROJECT_ROOT}/ansible/playbooks/harden.yml"
VALIDATE_PLAYBOOK="${PROJECT_ROOT}/ansible/playbooks/validate.yml"
VAULT_FILE="${PROJECT_ROOT}/ansible/group_vars/vault.yml"
VM_NAME="Linux-hardening-vm"

cd "${PROJECT_ROOT}"

echo "=== Linux server hardening deployment ==="
echo "Project root: ${PROJECT_ROOT}"

# Locate Vagrant. Prefer the Linux executable when running from WSL.
if command -v vagrant >/dev/null 2>&1; then
  VAGRANT_CMD="$(command -v vagrant)"
elif command -v vagrant.exe >/dev/null 2>&1; then
  VAGRANT_CMD="$(command -v vagrant.exe)"
else
  echo "ERROR: Vagrant was not found." >&2
  exit 1
fi

# Confirm all required tools are installed before making changes.
for cmd in ansible ansible-playbook ansible-inventory ansible-vault \
           ssh ssh-keygen chmod mktemp; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "ERROR: Required command not found: ${cmd}" >&2
    exit 1
  fi
done

# Confirm the deployment configuration files exist.
for file in \
  "${VAGRANT_DIR}/Vagrantfile" \
  "${INVENTORY}" \
  "${HARDEN_PLAYBOOK}" \
  "${VALIDATE_PLAYBOOK}" \
  "${VAULT_FILE}"; do
  if [[ ! -f "${file}" ]]; then
    echo "ERROR: Required file is missing: ${file}" >&2
    exit 1
  fi
done

# Create a private temporary file for the Vault password.
# The trap removes it on normal exit, failure, or common termination signals.
umask 077
VAULT_PASS_FILE="$(mktemp "${TMPDIR:-/tmp}/linux-hardening-vault.XXXXXX")"
chmod 600 "${VAULT_PASS_FILE}"
trap 'rm -f -- "${VAULT_PASS_FILE}"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Read the Vault password once without echoing it to the terminal.
echo
read -r -s -p "Enter Ansible Vault password: " VAULT_PASSWORD
echo

if [[ -z "${VAULT_PASSWORD}" ]]; then
  echo "ERROR: The Vault password cannot be empty." >&2
  exit 1
fi

# Write the password to the protected temporary file and clear the shell variable.
printf '%s' "${VAULT_PASSWORD}" > "${VAULT_PASS_FILE}"
unset VAULT_PASSWORD

# Pass the same temporary credential file to every Ansible command.
VAULT_ARGS=(--vault-password-file "${VAULT_PASS_FILE}")

echo
echo "=== Validate Ansible inventory ==="

# Confirm Ansible can parse the inventory and decrypt any required Vault data.
ansible-inventory \
  -i "${INVENTORY}" \
  --graph \
  "${VAULT_ARGS[@]}"

echo
echo "=== Ansible syntax checks ==="

# Check the hardening playbook before starting or changing the VM.
ansible-playbook \
  -i "${INVENTORY}" \
  "${HARDEN_PLAYBOOK}" \
  --syntax-check \
  "${VAULT_ARGS[@]}"

# Check the validation playbook with the same Vault credentials.
ansible-playbook \
  -i "${INVENTORY}" \
  "${VALIDATE_PLAYBOOK}" \
  --syntax-check \
  "${VAULT_ARGS[@]}"

echo
echo "=== Remove stale local Vagrant SSH host key ==="

# This is a disposable local lab using a forwarded SSH endpoint.
# Remove only this endpoint's saved host key before starting the VM.
# Host-key checking is disabled only for this local deployment.
ssh-keygen -R '[127.0.0.1]:2222' || true
export ANSIBLE_HOST_KEY_CHECKING=False

echo
echo "=== Create or start the Vagrant VM ==="

cd "${VAGRANT_DIR}"
"${VAGRANT_CMD}" up

echo
echo "=== Fix Vagrant SSH private-key permissions ==="

# SSH rejects private keys readable by other users.
# Restrict the Vagrant-managed key to the current user.
VAGRANT_KEY="${VAGRANT_DIR}/.vagrant/machines/${VM_NAME}/virtualbox/private_key"

if [[ ! -f "${VAGRANT_KEY}" ]]; then
  echo "ERROR: Vagrant SSH private key not found: ${VAGRANT_KEY}" >&2
  exit 1
fi

chmod 600 "${VAGRANT_KEY}"

# Display the permission mode, not the contents of the private key.
stat -c '%a %n' "${VAGRANT_KEY}"

cd "${PROJECT_ROOT}"

echo
echo "=== Wait for Ansible connectivity ==="

# Use Ansible's ping module to test SSH authentication and Python/module execution.
# Retry for up to 10 minutes, waiting 10 seconds between failed attempts.
CONNECTED=false

for ((attempt = 1; attempt <= 60; attempt++)); do
  echo "Connectivity attempt ${attempt}/60..."

  if ansible \
      -i "${INVENTORY}" \
      linux_servers \
      -m ansible.builtin.ping \
      "${VAULT_ARGS[@]}"; then
    CONNECTED=true
    break
  fi

  if (( attempt < 60 )); then
    sleep 10
  fi
done

if [[ "${CONNECTED}" != "true" ]]; then
  echo "ERROR: Ansible could not connect after the retry period." >&2
  echo "Check Vagrant status, SSH configuration, and private-key permissions." >&2
  exit 1
fi

echo
echo "=== Apply Linux hardening ==="

# Apply the hardening tasks using the same Vault password supplied at startup.
ansible-playbook \
  -i "${INVENTORY}" \
  "${HARDEN_PLAYBOOK}" \
  "${VAULT_ARGS[@]}"

echo
echo "=== Validate the hardening baseline ==="

# Run validation with the same credentials so encrypted variables remain available.
ansible-playbook \
  -i "${INVENTORY}" \
  "${VALIDATE_PLAYBOOK}" \
  "${VAULT_ARGS[@]}"

echo
echo "Deployment and validation completed successfully."
echo "VM: ${VM_NAME}"
echo "SSH endpoint: 127.0.0.1:2222"
echo "Initial SSH account: vagrant"
echo "Dedicated administrator: linuxadmin"
echo
echo "To stop the VM: cd '${VAGRANT_DIR}' && ${VAGRANT_CMD} halt"
echo "To destroy the VM: cd '${VAGRANT_DIR}' && ${VAGRANT_CMD} destroy -f"

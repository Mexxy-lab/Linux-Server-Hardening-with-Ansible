#!/usr/bin/env bash
# Project 2: Automated Linux Server Hardening
# Safely destroy the AWS and/or Azure Terraform environments.
# This script never destroys the local Vagrant VM.

set -Eeuo pipefail
umask 077

# Resolve the project root from the location of this script.
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# These paths belong specifically to the Linux Server Hardening project.
AWS_DIR="${PROJECT_ROOT}/aws/terraform"
AZURE_DIR="${PROJECT_ROOT}/azure/terraform"

# Store temporary destroy plans in a private directory.
# Terraform plans can contain sensitive infrastructure information.
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/linux-hardening-destroy.XXXXXX")"

cleanup() {
  # Remove temporary plans on exit; Terraform state is not deleted here.
  rm -rf -- "${TMP_DIR}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Track failures so one provider's failure does not prevent the other
# selected provider from being processed.
FAILURES=0

# Verify Terraform is installed.
if ! command -v terraform >/dev/null 2>&1; then
  echo "ERROR: Terraform is not installed or is not in PATH." >&2
  exit 1
fi

# Check that both project configurations exist before offering choices.
for dir in "${AWS_DIR}" "${AZURE_DIR}"; do
  if [[ ! -f "${dir}/main.tf" ]]; then
    echo "ERROR: Terraform configuration not found in ${dir}" >&2
    exit 1
  fi
done

echo "===================================================="
echo " Project 2: Linux Server Hardening - Cloud Teardown"
echo "===================================================="
echo
echo "AWS configuration:   ${AWS_DIR}"
echo "Azure configuration: ${AZURE_DIR}"
echo
echo "WARNING: This operation can permanently delete cloud resources."
echo "Terraform state and backend storage will be preserved."
echo "The local Vagrant VM will not be touched."
echo

# Let the operator choose the provider(s) to clean up.
echo "Choose which environment to destroy:"
echo "  1) AWS only"
echo "  2) Azure only"
echo "  3) Both AWS and Azure"
echo "  4) Cancel"
read -r -p "Selection [1-4]: " SELECTION

case "${SELECTION}" in
  1) PROVIDERS=("AWS") ;;
  2) PROVIDERS=("Azure") ;;
  3) PROVIDERS=("AWS" "Azure") ;;
  4)
    echo "Cancelled. No resources were changed."
    exit 0
    ;;
  *)
    echo "ERROR: Invalid selection. Nothing was destroyed." >&2
    exit 1
    ;;
esac

# Destroy one provider at a time, using a reviewed Terraform plan.
destroy_provider() {
  local provider="$1"
  local terraform_dir
  local plan_file
  local expected_confirmation
  local current_workspace
  local answer

  # Resolve the selected provider's Terraform directory.
  case "${provider}" in
    AWS)
      terraform_dir="${AWS_DIR}"
      expected_confirmation="destroy AWS"
      ;;
    Azure)
      terraform_dir="${AZURE_DIR}"
      expected_confirmation="destroy Azure"
      ;;
    *)
      echo "ERROR: Unsupported provider: ${provider}" >&2
      return 1
      ;;
  esac

  plan_file="${TMP_DIR}/${provider,,}-destroy.tfplan"

  echo
  echo "===================================================="
  echo " Preparing ${provider} teardown"
  echo "===================================================="

  # Check that the appropriate cloud CLI is available and show the
  # authenticated account before Terraform can delete anything.
  if [[ "${provider}" == "AWS" ]]; then
    if ! command -v aws >/dev/null 2>&1; then
      echo "ERROR: AWS CLI is required to verify the account." >&2
      return 1
    fi

    if ! aws sts get-caller-identity; then
      echo "ERROR: AWS authentication failed." >&2
      return 1
    fi
  else
    if ! command -v az >/dev/null 2>&1; then
      echo "ERROR: Azure CLI is required to verify the subscription." >&2
      return 1
    fi

    # Show the active subscription and tenant so the operator can verify them.
    if ! az account show \
      --query '{subscription:name,id:id,tenantId:tenantId}' \
      --output table; then
      echo "ERROR: Azure authentication failed." >&2
      return 1
    fi
  fi

  cd "${terraform_dir}"

  # Initialize the existing configuration and backend.
  # Do not delete or reconfigure backend storage automatically.
  echo
  echo "Initializing Terraform for ${provider}..."
  if ! terraform init -input=false; then
    echo "ERROR: Terraform initialization failed for ${provider}." >&2
    return 1
  fi

  # Show the active workspace because each workspace can manage
  # a different set of infrastructure resources.
  current_workspace="$(terraform workspace show)" || return 1
  echo "Terraform workspace: ${current_workspace}"

  # Generate a destroy plan without applying it.
  # Terraform can prompt for missing input variables when needed.
  echo
  echo "Generating ${provider} destroy plan..."
  if ! terraform plan -destroy -out="${plan_file}"; then
    echo "ERROR: Could not create the ${provider} destroy plan." >&2
    return 1
  fi

  # Display the exact saved plan before requesting authorization.
  echo
  echo "Reviewing the planned ${provider} deletions..."
  if ! terraform show "${plan_file}"; then
    echo "ERROR: Could not display the destroy plan." >&2
    return 1
  fi

  echo
  echo "Review the account, workspace, resources, and planned deletions."
  echo "To authorize this environment, type exactly: ${expected_confirmation}"
  read -r -p "Confirmation: " answer

  if [[ "${answer}" != "${expected_confirmation}" ]]; then
    echo "Skipped ${provider}; confirmation did not match."
    return 0
  fi

  # Apply only the saved plan that was displayed above.
  # Terraform will not silently generate a different destroy plan here.
  echo
  echo "Applying the reviewed ${provider} destroy plan..."
  if ! terraform apply -input=false "${plan_file}"; then
    echo "ERROR: Terraform destroy failed for ${provider}." >&2
    return 1
  fi

  echo "${provider} teardown completed successfully."
}

# Process every selected provider independently.
for provider in "${PROVIDERS[@]}"; do
  if ! destroy_provider "${provider}"; then
    echo "Teardown failed for ${provider}; continuing with remaining selections." >&2
    FAILURES=$((FAILURES + 1))
  fi
done

# Summarize the result.
echo
echo "===================================================="
if (( FAILURES > 0 )); then
  echo "Teardown finished with ${FAILURES} provider failure(s)."
  echo "Inspect the errors and cloud consoles for remaining resources."
  exit 1
else
  echo "All selected teardown workflows finished."
  echo "Review each provider's output to confirm whether deletion occurred."
fi

echo
echo "Remember to check for any remaining billable resources."
echo "Terraform state and remote backend resources were not intentionally deleted."
echo "The local Vagrant VM was not affected."

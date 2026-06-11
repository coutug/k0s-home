# Deploys sops-secret, flux-operator and flux-instance
#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

NAMESPACE="flux-system"
RELEASE_NAME="flux-operator"
CHART="oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator"
VALUES_FILE="flux-operator.yaml"
SOPS_SECRET_FILE="sops-secret.yaml"
FLUX_INSTANCE_FILE="flux-instance.yaml"

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "${command_name}" >&2
    exit 1
  fi
}

require_file() {
  local file_path="$1"

  if [[ ! -f "${file_path}" ]]; then
    printf 'Missing required file: %s\n' "${file_path}" >&2
    exit 1
  fi
}

confirm_context() {
  local current_context="$1"

  if [[ "${BOOTSTRAP_ASSUME_YES:-}" == "1" ]]; then
    return
  fi

  printf 'Kubernetes context: %s\n' "${current_context}"
  printf 'Bootstrap Flux on this cluster? [y/N] '
  read -r answer

  case "${answer}" in
    y|Y|yes|YES) ;;
    *)
      printf 'Aborted.\n' >&2
      exit 1
      ;;
  esac
}

require_command helm
require_command kubectl

require_file "${VALUES_FILE}"
require_file "${SOPS_SECRET_FILE}"
require_file "${FLUX_INSTANCE_FILE}"

current_context="$(kubectl config current-context)"
confirm_context "${current_context}"

helm upgrade --install "${RELEASE_NAME}" "${CHART}" \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  --wait \
  --timeout 5m \
  --values "${VALUES_FILE}"

kubectl apply --namespace "${NAMESPACE}" --filename "${SOPS_SECRET_FILE}"
kubectl apply --namespace "${NAMESPACE}" --filename "${FLUX_INSTANCE_FILE}"

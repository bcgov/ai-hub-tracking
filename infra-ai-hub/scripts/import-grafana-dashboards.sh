#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Usage: $(basename "$0") \
  --resource-group <rg> \
  --grafana-name <name> \
  --storage-account <account> \
  --container <container> \
  --apim-dashboard-enabled <true|false> \
  --ai-dashboard-enabled <true|false> \
  --apim-dashboard-blob <name> \
  --ai-dashboard-blob <name>
EOF
}

RESOURCE_GROUP=""
GRAFANA_NAME=""
STORAGE_ACCOUNT=""
CONTAINER_NAME=""
APIM_ENABLED="false"
AI_ENABLED="false"
APIM_BLOB=""
AI_BLOB=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --resource-group)
      RESOURCE_GROUP="$2"
      shift 2
      ;;
    --grafana-name)
      GRAFANA_NAME="$2"
      shift 2
      ;;
    --storage-account)
      STORAGE_ACCOUNT="$2"
      shift 2
      ;;
    --container)
      CONTAINER_NAME="$2"
      shift 2
      ;;
    --apim-dashboard-enabled)
      APIM_ENABLED="$2"
      shift 2
      ;;
    --ai-dashboard-enabled)
      AI_ENABLED="$2"
      shift 2
      ;;
    --apim-dashboard-blob)
      APIM_BLOB="$2"
      shift 2
      ;;
    --ai-dashboard-blob)
      AI_BLOB="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac

done

if [[ -z "$RESOURCE_GROUP" || -z "$GRAFANA_NAME" || -z "$STORAGE_ACCOUNT" || -z "$CONTAINER_NAME" ]]; then
  usage
  exit 1
fi

WORK_DIR="$(mktemp -d -p "$SCRIPT_DIR")"
trap 'rm -rf "$WORK_DIR"' EXIT

DATASOURCE_NAME="Azure Monitor"
DATASOURCE_TYPE="grafana-azure-monitor-datasource"

DATASOURCE_COUNT="$(az grafana data-source list --resource-group "$RESOURCE_GROUP" --name "$GRAFANA_NAME" --query "[?name=='${DATASOURCE_NAME}'] | length(@)" -o tsv)"
if [[ -z "$DATASOURCE_COUNT" || "$DATASOURCE_COUNT" == "0" ]]; then
  SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
  TENANT_ID="$(az account show --query tenantId -o tsv)"

  cat <<EOF > "${WORK_DIR}/datasource.json"
{
  "name": "${DATASOURCE_NAME}",
  "type": "${DATASOURCE_TYPE}",
  "access": "proxy",
  "jsonData": {
    "azureAuthType": "msi",
    "cloudName": "azuremonitor",
    "subscriptionId": "${SUBSCRIPTION_ID}",
    "tenantId": "${TENANT_ID}"
  }
}
EOF

  DATASOURCE_PAYLOAD="$(tr -d '\r\n' < "${WORK_DIR}/datasource.json")"
  az grafana data-source create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$GRAFANA_NAME" \
    --definition "$DATASOURCE_PAYLOAD" \
    --only-show-errors \
    --output none
fi

import_dashboard() {
  local blob_name="$1"
  local dashboard_label="$2"
  local local_file="${WORK_DIR}/${blob_name}"
  local definition

  if ! az storage blob download \
    --account-name "$STORAGE_ACCOUNT" \
    --container-name "$CONTAINER_NAME" \
    --name "$blob_name" \
    --file "$local_file" \
    --auth-mode login \
    --only-show-errors \
    --output none 2>/dev/null; then

    ACCOUNT_KEY="$(az storage account keys list --resource-group "$RESOURCE_GROUP" --account-name "$STORAGE_ACCOUNT" --query "[0].value" -o tsv)"
    if [[ -z "$ACCOUNT_KEY" || "$ACCOUNT_KEY" == "null" ]]; then
      echo "Failed to download blob and could not retrieve storage account key." >&2
      exit 1
    fi

    az storage blob download \
      --account-name "$STORAGE_ACCOUNT" \
      --account-key "$ACCOUNT_KEY" \
      --container-name "$CONTAINER_NAME" \
      --name "$blob_name" \
      --file "$local_file" \
      --auth-mode key \
      --only-show-errors \
      --output none
  fi

  local attempt

  for attempt in {1..10}; do
    if az grafana dashboard import \
      --resource-group "$RESOURCE_GROUP" \
      --name "$GRAFANA_NAME" \
      --definition "$local_file" \
      --overwrite true \
      --only-show-errors \
      --output none; then
      return 0
    fi

    if [[ "$attempt" -lt 10 ]]; then
      echo "Grafana dashboard import failed. Waiting for role propagation... attempt ${attempt}/10" >&2
      sleep 15
      continue
    fi

    echo "Failed to import dashboard: ${dashboard_label}" >&2
    exit 1
  done
}

if [[ "$APIM_ENABLED" == "true" && -n "$APIM_BLOB" ]]; then
  import_dashboard "$APIM_BLOB" "APIM Gateway"
fi

if [[ "$AI_ENABLED" == "true" && -n "$AI_BLOB" ]]; then
  import_dashboard "$AI_BLOB" "AI Usage"
fi

echo "Grafana dashboards imported successfully."

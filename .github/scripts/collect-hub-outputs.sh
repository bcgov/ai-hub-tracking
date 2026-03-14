#!/usr/bin/env bash

set -euo pipefail

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "Environment variable '$name' is required." >&2
    exit 1
  fi
}

require_env BACKEND_STORAGE_ACCOUNT
require_env BACKEND_CONTAINER
require_env HUB_ENV

shared_blob_name="ai-services-hub/${HUB_ENV}/shared.tfstate"
apim_blob_name="ai-services-hub/${HUB_ENV}/apim.tfstate"

container_exists="$(az storage container exists \
  --account-name "$BACKEND_STORAGE_ACCOUNT" \
  --name "$BACKEND_CONTAINER" \
  --auth-mode login \
  --query exists \
  --output tsv)"
if [[ "$container_exists" != "true" ]]; then
  echo "Container '$BACKEND_CONTAINER' not found in storage account '$BACKEND_STORAGE_ACCOUNT'." >&2
  exit 0
fi

shared_blob_exists="$(az storage blob exists \
  --account-name "$BACKEND_STORAGE_ACCOUNT" \
  --container-name "$BACKEND_CONTAINER" \
  --name "$shared_blob_name" \
  --auth-mode login \
  --query exists \
  --output tsv)"
if [[ "$shared_blob_exists" != "true" ]]; then
  echo "Blob '$shared_blob_name' not found in container '$BACKEND_CONTAINER'." >&2
  exit 0
fi

apim_blob_exists="$(az storage blob exists \
  --account-name "$BACKEND_STORAGE_ACCOUNT" \
  --container-name "$BACKEND_CONTAINER" \
  --name "$apim_blob_name" \
  --auth-mode login \
  --query exists \
  --output tsv)"
if [[ "$apim_blob_exists" != "true" ]]; then
  echo "Blob '$apim_blob_name' not found in container '$BACKEND_CONTAINER'." >&2
  exit 0
fi

az storage blob download \
  --account-name "$BACKEND_STORAGE_ACCOUNT" \
  --container-name "$BACKEND_CONTAINER" \
  --name "$shared_blob_name" \
  --auth-mode login --file /tmp/shared.tfstate --output none
az storage blob download \
  --account-name "$BACKEND_STORAGE_ACCOUNT" \
  --container-name "$BACKEND_CONTAINER" \
  --name "$apim_blob_name" \
  --auth-mode login --file /tmp/apim.tfstate --output none

hub_kv_id="$(jq -r '.outputs.hub_key_vault_id.value // empty' /tmp/shared.tfstate)"
hub_kv_url="$(jq -r '.outputs.hub_key_vault_uri.value // empty' /tmp/shared.tfstate)"
apim_url="$(jq -r '.outputs.apim_gateway_url.value // empty' /tmp/apim.tfstate)"

if [[ -z "$hub_kv_id" ]]; then
  echo "::warning::hub_key_vault_id could not be found in shared tfstate for environment '$HUB_ENV'" >&2
fi
if [[ -z "$hub_kv_url" ]]; then
  echo "::warning::hub_key_vault_uri could not be found in shared tfstate for environment '$HUB_ENV'" >&2
fi
if [[ -z "$apim_url" ]]; then
  echo "::warning::apim_gateway_url could not be found in apim tfstate for environment '$HUB_ENV'" >&2
fi

if [[ -z "$hub_kv_id" || -z "$hub_kv_url" || -z "$apim_url" ]]; then
  echo "Required Terraform outputs are missing or empty for environment '$HUB_ENV', skipping output." >&2
  exit 0
fi

echo "hub_kv_id=$hub_kv_id" >> "$GITHUB_OUTPUT"
echo "hub_kv_url=$hub_kv_url" >> "$GITHUB_OUTPUT"
echo "apim_url=$apim_url" >> "$GITHUB_OUTPUT"

rm -f /tmp/shared.tfstate /tmp/apim.tfstate
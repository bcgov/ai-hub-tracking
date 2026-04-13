#!/usr/bin/env bash
# azureml-init.sh — Stage a model from an Azure ML registry to the persistent model cache.
#
# Expected environment variables (all required unless noted):
#   AZUREML_REGISTRY_NAME   : AML registry short name (e.g. "my-ml-registry")
#   AZUREML_MODEL_NAME      : Model asset name in the registry
#   AZUREML_MODEL_VERSION   : Model asset version (e.g. "1", "2024-11-01")
#   AZUREML_DOWNLOAD_PARENT : Parent directory on /model-cache where az ml model download
#                             will create the {model_name}/ subfolder
#   AZUREML_MODEL_ROOT      : Final model root = AZUREML_DOWNLOAD_PARENT/AZUREML_MODEL_NAME
#   AZUREML_CLIENT_ID       : Client ID of the user-assigned managed identity for az login
#   AZUREML_SUBSCRIPTION_ID : (Optional) AML registry subscription; defaults to current
#
# az ml model download creates: {download_path}/{model_name}/...
# This script downloads to a temp dir, validates HF layout (config.json), then moves
# atomically to AZUREML_MODEL_ROOT and writes a .download-complete marker.

set -euo pipefail

if [ -f "$AZUREML_MODEL_ROOT/.download-complete" ]; then
  echo "Model already staged at $AZUREML_MODEL_ROOT — skipping download."
  exit 0
fi

echo "Logging in with user-assigned managed identity (client ID: $AZUREML_CLIENT_ID)..."
az login --identity --username "$AZUREML_CLIENT_ID" --only-show-errors >/dev/null

SUBSCRIPTION="${AZUREML_SUBSCRIPTION_ID:-}"
if [ -n "$SUBSCRIPTION" ]; then
  echo "Setting subscription to $SUBSCRIPTION..."
  az account set --subscription "$SUBSCRIPTION" --only-show-errors >/dev/null
fi

TEMP_DIR="$AZUREML_DOWNLOAD_PARENT/.tmp-$$"
mkdir -p "$TEMP_DIR"

echo "Downloading $AZUREML_MODEL_NAME (v$AZUREML_MODEL_VERSION) from registry $AZUREML_REGISTRY_NAME..."
az ml model download \
  --registry-name "$AZUREML_REGISTRY_NAME" \
  --name "$AZUREML_MODEL_NAME" \
  --version "$AZUREML_MODEL_VERSION" \
  --download-path "$TEMP_DIR" \
  --only-show-errors

# az ml model download creates {TEMP_DIR}/{model_name}/... — validate and move atomically.
DOWNLOADED="$TEMP_DIR/$AZUREML_MODEL_NAME"

if [ ! -f "$DOWNLOADED/config.json" ]; then
  echo "ERROR: Downloaded model is missing config.json." >&2
  echo "Only HuggingFace-format model assets (with config.json at the root) are supported." >&2
  rm -rf "$TEMP_DIR"
  exit 1
fi

touch "$DOWNLOADED/.download-complete"
mkdir -p "$AZUREML_DOWNLOAD_PARENT"
mv "$DOWNLOADED" "$AZUREML_MODEL_ROOT"
rmdir "$TEMP_DIR" 2>/dev/null || true

echo "Model staged successfully at $AZUREML_MODEL_ROOT"

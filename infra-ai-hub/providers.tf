#############################################
# AzureRM Provider Configuration (Terraform)
#############################################
#
# This file configures the Terraform AzureRM provider, including:
# - Authentication inputs (subscription / tenant / client ID)
# - Safety / lifecycle behaviors for certain Azure resource types via `features {}`
#
# Notes on authentication (OIDC / Workload Identity Federation):
# - This repo is set up to support OIDC-based auth (no long-lived secrets) when run from CI.
# - In GitHub Actions + Microsoft Entra Workload Identity Federation, you typically provide:
#   - AZURE_CLIENT_ID (or the app/managed identity client ID)
#   - AZURE_TENANT_ID (directory/tenant ID)
#   - AZURE_SUBSCRIPTION_ID
#   Microsoft Learn: https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation-create-trust-user-assigned-managed-identity#configure-a-federated-identity-credential-on-a-user-assigned-managed-identity
#
# - `subscription_id`, `tenant_id`, `client_id`, and `use_oidc` are wired via Terraform variables so
#   the same configuration can run locally (developer auth) or in CI (OIDC).
#
provider "azurerm" {
  features {
    #########################################
    # Key Vault
    #########################################
    # Key Vaults commonly use soft-delete and (optionally) purge protection.
    # - Soft delete retains a deleted vault for a retention period; it can be recovered or purged.
    # - Purge protection prevents purging until retention elapses.
    # Microsoft Learn: https://learn.microsoft.com/en-us/azure/key-vault/general/key-vault-recovery
    key_vault {
      # In general, Terraform can be configured to purge (permanently delete) a Key Vault when it
      # is destroyed. That behavior is often useful in dev/test environments where you want to
      # quickly reuse globally unique Key Vault names.
      #
      # In this deployment, however, purge behavior is governed by organizational / platform policy,
      # so we do NOT request purging on destroy here. Soft-deleted vaults and name reuse will be
      # subject to those external policies and retention settings.
      purge_soft_delete_on_destroy = false # policy-driven: purging on destroy is disabled here

      # If a vault name already exists in a soft-deleted state (common when names are globally
      # unique and a prior deployment deleted it), attempt to recover it automatically.
      # This helps make `apply` more idempotent in dev/test where environments are recreated.
      recover_soft_deleted_key_vaults = true
    }

    #########################################
    # Resource Groups
    #########################################
    # Azure Resource Group deletion is irreversible (the RG itself cannot be recovered).
    # Microsoft Learn: https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/delete-resource-group
    resource_group {
      # Guardrail: refuse to delete a resource group if it still contains resources.
      # This prevents accidental blast-radius deletions if a config mistake targets the wrong RG.
      prevent_deletion_if_contains_resources = true
    }

    #########################################
    # Log Analytics Workspaces
    #########################################
    # Log Analytics workspaces support soft-delete (recoverable during the retention window), and
    # can also be permanently deleted to immediately free the workspace name.
    # Microsoft Learn: https://learn.microsoft.com/en-us/azure/azure-monitor/logs/delete-workspace
    log_analytics_workspace {
      # When Terraform destroys a workspace, permanently delete it instead of leaving it in
      # soft-delete. This is primarily useful for dev/test where you frequently recreate the same
      # workspace name.
      #
      # Important: Permanent deletion is non-recoverable.
      permanently_delete_on_destroy = false
    }

    #########################################
    # Azure AI Services / Cognitive Services accounts
    #########################################
    cognitive_account {
      # Attempt to purge a soft-deleted cognitive services account when Terraform destroys it.
      # This can help with rapid redeploys in dev/test where names may be reused.
      #
      # Important: If the service or policy enforces retention / soft-delete constraints, purging
      # may be blocked and destroy may require waiting.
      purge_soft_delete_on_destroy = true
    }

    #########################################
    # ARM Template Deployments (Microsoft.Resources/deployments)
    #########################################
    template_deployment {
      # When destroying a template deployment resource, attempt to also delete nested items that
      # were created by that deployment. This behavior reduces orphaned resources when a deployment
      # is used as an implementation detail.
      #
      # Background on deletion semantics: Azure Resource Manager determines a deletion order and
      # resource group deletions are irreversible.
      # Microsoft Learn: https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/delete-resource-group
      delete_nested_items_during_deletion = true
    }
  }

  # Authentication scope
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id

  # OIDC / workload identity federation toggle.
  # When true, the provider authenticates via OpenID Connect token exchange rather than a client
  # secret. This aligns with modern CI hardening practices (no long-lived secrets).
  use_oidc = var.use_oidc

  # Client ID of the Entra application or managed identity used by Terraform.
  client_id = var.client_id
}

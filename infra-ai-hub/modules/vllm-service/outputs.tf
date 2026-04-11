# -----------------------------------------------------------------------------
# Private GPU vLLM on Azure Container Apps Module Outputs
# -----------------------------------------------------------------------------

output "container_app_environment_id" {
  description = "Resource ID of the vLLM Container Apps environment"
  value       = azurerm_container_app_environment.vllm.id
}

output "container_registry_name" {
  description = "Name of the Azure Container Registry mirroring the vLLM image"
  value       = azurerm_container_registry.vllm.name
}

output "container_registry_login_server" {
  description = "Login server of the Azure Container Registry mirroring the vLLM image"
  value       = azurerm_container_registry.vllm.login_server
}

output "container_app_environment_name" {
  description = "Name of the vLLM Container Apps environment"
  value       = azurerm_container_app_environment.vllm.name
}

output "private_endpoint_name" {
  description = "Name of the private endpoint attached to the vLLM Container Apps environment"
  value       = azurerm_private_endpoint.vllm_environment.name
}

output "container_app_name" {
  description = "Name of the vLLM Container App"
  value       = azurerm_container_app.vllm.name
}

output "container_app_fqdn" {
  description = "FQDN of the vLLM Container App ingress"
  value       = azurerm_container_app.vllm.ingress[0].fqdn
}

output "endpoint" {
  description = "Private HTTPS base URL exposed by the vLLM Container App"
  value       = format("https://%s", azurerm_container_app.vllm.ingress[0].fqdn)
}

output "openai_endpoint" {
  description = "Private OpenAI-compatible /v1 endpoint exposed by the vLLM Container App"
  value       = format("https://%s/v1", azurerm_container_app.vllm.ingress[0].fqdn)
}

output "container_image" {
  description = "Mirrored container image used by the vLLM Container App"
  value       = local.mirrored_image
}

output "model_id" {
  description = "Hugging Face model ID configured for the vLLM Container App"
  value       = var.model_id
}

output "max_model_len" {
  description = "Maximum sequence length exposed by the vLLM server"
  value       = var.max_model_len
}

output "model_cache_storage_account_name" {
  description = "Storage account name backing the persistent Hugging Face model cache"
  value       = azurerm_storage_account.model_cache.name
}

output "model_cache_share_name" {
  description = "Azure Files share name backing the persistent Hugging Face model cache"
  value       = azurerm_storage_share.model_cache.name
}

output "workload_profile_type" {
  description = "GPU workload profile type used by the Container App"
  value       = var.workload_profile_type
}

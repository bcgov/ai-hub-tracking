locals {
  vllm_config        = try(var.shared_config.vllm, {})
  vllm_enabled       = try(local.vllm_config.enabled, false)
  use_azureml_source = local.vllm_enabled && try(local.vllm_config.model_source, "huggingface") == "azureml_registry"
}

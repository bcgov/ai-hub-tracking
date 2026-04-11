locals {
  vllm_config  = try(var.shared_config.vllm, {})
  vllm_enabled = try(local.vllm_config.enabled, false)
}

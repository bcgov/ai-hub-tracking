output "vllm_service" {
  description = "vLLM Container App service details (null when not deployed)"
  value = length(module.vllm_service) > 0 ? {
    container_app_fqdn    = module.vllm_service[0].container_app_fqdn
    endpoint              = module.vllm_service[0].endpoint
    openai_endpoint       = module.vllm_service[0].openai_endpoint
    model_id              = module.vllm_service[0].model_id
    max_model_len         = module.vllm_service[0].max_model_len
    workload_profile_type = module.vllm_service[0].workload_profile_type
  } : null
}

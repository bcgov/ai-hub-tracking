# -----------------------------------------------------------------------------
# Private GPU vLLM on Azure Container Apps Module Variables
# -----------------------------------------------------------------------------

variable "app_name" {
  description = "Name of the application, used for resource naming"
  type        = string
  nullable    = false
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  nullable    = false
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  nullable    = false
}

variable "infrastructure_subnet_id" {
  description = "Delegated subnet ID for the Container Apps environment"
  type        = string
  nullable    = false
}

variable "private_endpoint_subnet_id" {
  description = "Subnet ID for the Container Apps environment private endpoint"
  type        = string
  nullable    = false
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics Workspace ID for Container Apps diagnostics"
  type        = string
  nullable    = false
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  nullable    = false
}

variable "image" {
  description = "Source vLLM container image used as the upstream base image mirrored or rebuilt into the module-managed Azure Container Registry"
  type        = string
  default     = "vllm/vllm-openai:latest"
}

variable "model_id" {
  description = "Exact Hugging Face model ID served by the vLLM container"
  type        = string
  default     = "google/gemma-4-31B-it"
}

variable "offline_mode" {
  description = "Whether to force Hugging Face and Transformers into cache-only offline mode so startup uses only files already present on the mounted Azure Files share"
  type        = bool
  default     = false
}

variable "max_model_len" {
  description = "Maximum sequence length exposed by the deployed vLLM server"
  type        = number
  default     = 32768

  validation {
    condition     = var.max_model_len >= 4096
    error_message = "max_model_len must be at least 4096 tokens."
  }
}

variable "gpu_memory_utilization" {
  description = "Target fraction of GPU memory that vLLM is allowed to reserve"
  type        = number
  default     = 0.9

  validation {
    condition     = var.gpu_memory_utilization >= 0.5 && var.gpu_memory_utilization < 1
    error_message = "gpu_memory_utilization must be between 0.5 and 1.0."
  }
}

variable "quantization" {
  description = "vLLM quantization backend passed as --quantization <value>. Set to null (default) to disable quantization. Must point to a matching pre-quantized HuggingFace model repo — vLLM does not quantize BF16 models on the fly. Common values: awq, gptq, fp8, bitsandbytes."
  type        = string
  default     = null

  validation {
    condition     = var.quantization == null || trimspace(var.quantization) != ""
    error_message = "quantization must be null or a non-empty string matching a vLLM-supported quantization backend."
  }
}

variable "huggingface_token" {
  description = "Optional Hugging Face access token injected into the container as HF_TOKEN for higher rate limits or gated models. In hub deployments, source this from the hub Key Vault (data.azurerm_key_vault_secret) in the calling stack rather than storing in tfvars."
  type        = string
  default     = ""
  sensitive   = true
}

variable "registry_sku" {
  description = "SKU for the module-managed Azure Container Registry used to mirror the vLLM image"
  type        = string
  default     = "Basic"

  validation {
    condition     = contains(["Basic", "Standard"], var.registry_sku)
    error_message = "registry_sku must be either Basic or Standard."
  }
}

variable "model_cache_share_quota_gb" {
  description = "Quota in GiB for the Azure Files share that persists Hugging Face model cache data across revisions and replica restarts"
  type        = number
  default     = 64

  validation {
    condition     = var.model_cache_share_quota_gb >= 20
    error_message = "model_cache_share_quota_gb must be at least 20 GiB."
  }
}

variable "workload_profile_name" {
  description = "Logical name of the GPU workload profile inside the Container Apps environment"
  type        = string
  default     = "gpu"
}

variable "workload_profile_type" {
  description = "GPU workload profile type to use for the vLLM Container App"
  type        = string
  default     = "Consumption-GPU-NC24-A100"

  validation {
    condition = contains([
      "Consumption-GPU-NC24-A100",
      "Consumption-GPU-NC8as-T4",
    ], var.workload_profile_type)
    error_message = "workload_profile_type must be either Consumption-GPU-NC24-A100 or Consumption-GPU-NC8as-T4."
  }
}

variable "min_replicas" {
  description = "Minimum number of vLLM replicas. Defaults to 0 (scale-to-zero) for cost efficiency. Note: GPU cold-start for large models (e.g. Gemma 4 31B) takes 5-10 minutes — set to 1 if cold-start latency is unacceptable for your workload."
  type        = number
  default     = 0
}

variable "max_replicas" {
  description = "Maximum number of vLLM replicas"
  type        = number
  default     = 1
}

variable "scripts_dir" {
  description = "Path to the scripts directory containing wait-for-dns-zone.sh"
  type        = string
  nullable    = false
}

variable "private_endpoint_dns_wait" {
  description = "Configuration for waiting on policy-managed DNS zone groups"
  type = object({
    timeout       = optional(string, "15m")
    poll_interval = optional(string, "30s")
  })
  default = {}
}

variable "wait_for_private_endpoint_dns_zone_group" {
  description = "Whether Terraform should block on policy-managed private DNS zone-group attachment before completing the deployment"
  type        = bool
  default     = false
}

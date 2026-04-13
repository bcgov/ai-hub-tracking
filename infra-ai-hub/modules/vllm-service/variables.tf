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
  description = <<-EOT
    Canonical API-facing model identifier. For model_source = "huggingface": the Hugging Face
    repo ID passed directly to vllm serve as the --model argument (e.g. "google/gemma-4-31B-it").
    For model_source = "azureml_registry": the name exposed via --served-model-name so tenants
    can use the same model= value regardless of the underlying source. In both cases this is the
    value tenants set in the model= field when calling the API.
  EOT
  type        = string
  default     = "google/gemma-4-31B-it"
}

variable "model_source" {
  description = <<-EOT
    Source for the model weights served by vLLM. Valid values:
    - "huggingface"      : Download model weights from Hugging Face Hub at container startup
                           (default). Set huggingface_token for gated models. Toggle offline_mode
                           after initial download to prevent repeated HF Hub calls.
    - "azureml_registry" : Stage model weights from an Azure ML registry using a user-assigned
                           managed identity and az ml model download in an init container.
                           Requires azureml_registry to be configured. The model asset must be in
                           HuggingFace snapshot format — it must contain config.json at the root of
                           the downloaded directory for vLLM to load it.
  EOT
  type        = string
  default     = "huggingface"

  validation {
    condition     = contains(["huggingface", "azureml_registry"], var.model_source)
    error_message = "model_source must be either \"huggingface\" or \"azureml_registry\"."
  }
}

variable "azureml_registry" {
  description = <<-EOT
    Azure Machine Learning registry configuration. Required when model_source = "azureml_registry".
    - registry_name        : Short name of the AML registry (e.g. "my-ml-registry").
    - model_name           : Name of the model asset in the registry. Must match exactly the asset
                             name used when registering with az ml model create.
    - model_version        : Version label of the model asset (e.g. "1", "2024-11-01").
    - registry_resource_id : Full ARM resource ID of the AML registry. Used by the calling stack to
                             create the AzureML Registry User RBAC assignment scoped to this registry.
    - subscription_id      : Optional. Azure subscription containing the AML registry. Defaults to
                             the current deployment subscription when omitted or empty.
  EOT
  type = object({
    registry_name        = string
    model_name           = string
    model_version        = string
    registry_resource_id = string
    subscription_id      = optional(string, "")
  })
  default = null
}

variable "offline_mode" {
  description = <<-EOT
    Controls whether the vLLM container runs in offline mode (no network calls to
    model registries at runtime).

    When true (default): for HuggingFace source, an init container pre-downloads
    the model to the persistent Azure Files cache on first deployment and writes a
    .download-complete marker. Subsequent container restarts skip the download. The
    main container always starts with HF_HUB_OFFLINE=1 and TRANSFORMERS_OFFLINE=1,
    guaranteeing zero re-downloads on restart regardless of network availability.

    When false: vLLM downloads the model inline during startup. The HuggingFace
    library caches to Azure Files, but each restart performs a network check against
    the HuggingFace Hub to verify model freshness.

    For model_source = "azureml_registry", the AzureML init container always handles
    the download regardless of this setting. offline_mode controls whether
    HF_HUB_OFFLINE is set on the main container — recommended to prevent spurious
    tokenizer fetch calls.
  EOT
  type        = bool
  default     = true
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
  description = "Optional Hugging Face access token injected into the container as HF_TOKEN for higher rate limits or gated models. Only used when model_source = \"huggingface\". In hub deployments, source this from the hub Key Vault (data.azurerm_key_vault_secret) in the calling stack rather than storing in tfvars."
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
  description = "Quota in GiB for the Azure Files share that persists model cache data across revisions and replica restarts. For huggingface source this holds HF Hub files; for azureml_registry source this holds the staged model directory."
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

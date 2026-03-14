variable "name_prefix" {
  description = "Prefix for all resource names (e.g. 'aihub-dev')."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group where the Container App is deployed."
  type        = string
}

variable "container_app_environment_id" {
  description = "Resource ID of the shared Container App Environment."
  type        = string
}

variable "container_registry_url" {
  description = "Container registry URL (without trailing slash)."
  type        = string
  default     = "ghcr.io"
}

variable "container_image_name" {
  description = "Full image name within the registry (e.g. 'bcgov/ai-hub-tracking/jobs/pii-redaction-service')."
  type        = string
}

variable "container_image_tag" {
  description = "Container image tag. Use 'latest' for rolling deployments or a semver tag for pinned releases."
  type        = string
  default     = "latest"
}

variable "cpu" {
  description = "vCPU allocation per replica."
  type        = number
  default     = 0.5
}

variable "memory" {
  description = "Memory allocation per replica (e.g. '1Gi')."
  type        = string
  default     = "1Gi"
}

variable "min_replicas" {
  description = "Minimum number of Container App replicas."
  type        = number
  default     = 1
}

variable "max_replicas" {
  description = "Maximum number of Container App replicas."
  type        = number
  default     = 5
}

# ---------------------------------------------------------------------------
# Language Service configuration
# ---------------------------------------------------------------------------

variable "language_endpoint" {
  description = "Azure Language Service endpoint URL (PII_LANGUAGE_ENDPOINT)."
  type        = string
}

variable "language_service_id" {
  description = "Resource ID of the Language Service — used for the Cognitive Services User RBAC assignment."
  type        = string
}

variable "language_api_version" {
  description = "Language API version string (PII_LANGUAGE_API_VERSION)."
  type        = string
  default     = "2025-11-15-preview"
}

# ---------------------------------------------------------------------------
# Processing limits
# ---------------------------------------------------------------------------

variable "per_batch_timeout_seconds" {
  description = "Timeout in seconds for each Language API batch call (PII_PER_BATCH_TIMEOUT_SECONDS)."
  type        = number
  default     = 10
}

variable "total_processing_timeout_seconds" {
  description = "Overall deadline in seconds for processing all batches (PII_TOTAL_PROCESSING_TIMEOUT_SECONDS)."
  type        = number
  default     = 55
}

variable "max_sequential_batches" {
  description = "Maximum number of sequential Language API calls. Requests requiring more batches receive HTTP 413."
  type        = number
  default     = 10
}

variable "max_doc_chars" {
  description = "Maximum characters per Language API document before word-boundary chunking (PII_MAX_DOC_CHARS)."
  type        = number
  default     = 5000
}

variable "max_docs_per_call" {
  description = "Maximum documents per Language API call (PII_MAX_DOCS_PER_CALL)."
  type        = number
  default     = 5
}

variable "log_level" {
  description = "Application log level (PII_LOG_LEVEL). One of: DEBUG, INFO, WARNING, ERROR."
  type        = string
  default     = "INFO"
}

variable "tags" {
  description = "Resource tags."
  type        = map(string)
  default     = {}
}

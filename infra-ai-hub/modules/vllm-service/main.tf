# -----------------------------------------------------------------------------
# Private GPU vLLM on Azure Container Apps
# -----------------------------------------------------------------------------

locals {
  normalized_app_name            = substr(lower(replace(var.app_name, "-", "")), 0, 11)
  container_app_environment_name = "${var.app_name}-gpu-vllm-env"
  container_app_name             = "${var.app_name}-gpu-vllm"
  infrastructure_rg_name         = substr("ME-${var.resource_group_name}-${local.container_app_environment_name}", 0, 90)
  container_registry_name        = substr("${local.normalized_app_name}vllm${random_string.resource_suffix.result}", 0, 50)
  model_cache_storage_name       = substr("${local.normalized_app_name}vllmsa${random_string.resource_suffix.result}", 0, 24)
  model_cache_share_name         = "vllm-model-cache"
  environment_storage_name       = "modelcache"
  image_has_registry_host        = length(regexall("^[^/]+\\.[^/]+/.+$", var.image)) > 0
  use_gemma4_compat_image        = length(regexall("(^|/)gemma-4", var.model_id)) > 0
  source_image                   = local.image_has_registry_host ? var.image : "docker.io/${var.image}"
  repository_and_tag             = local.image_has_registry_host ? join("/", slice(split("/", var.image), 1, length(split("/", var.image)))) : var.image
  gemma4_repository_and_tag      = "vllm/vllm-openai:gemma4-compatible"
  effective_repository_and_tag   = local.use_gemma4_compat_image ? local.gemma4_repository_and_tag : local.repository_and_tag
  mirrored_image                 = "${azurerm_container_registry.vllm.login_server}/${local.effective_repository_and_tag}"
  module_dir                     = replace(path.module, "\\", "/")
  compat_image_hash              = local.use_gemma4_compat_image ? md5(join(":", [filemd5("${path.module}/Dockerfile.gemma4"), filemd5("${path.module}/aca_proxy.py")])) : null

  workload_profile_resources = {
    "Consumption-GPU-NC24-A100" = {
      cpu    = 24
      memory = "220Gi"
    }
    "Consumption-GPU-NC8as-T4" = {
      cpu    = 8
      memory = "56Gi"
    }
  }

  vllm_service_port      = 8000
  vllm_backend_port      = local.use_gemma4_compat_image ? 8001 : local.vllm_service_port
  vllm_backend_host      = local.use_gemma4_compat_image ? "127.0.0.1" : "0.0.0.0"
  vllm_container_command = local.use_gemma4_compat_image ? ["python3", "/opt/aca_proxy.py"] : null
  model_cache_root       = "/model-cache"
  huggingface_home       = "/model-cache/huggingface"
  huggingface_hub_path   = "/model-cache/huggingface/hub"
}

resource "random_string" "resource_suffix" {
  length  = 5
  lower   = true
  upper   = false
  numeric = true
  special = false

  keepers = {
    app_name            = var.app_name
    resource_group_name = var.resource_group_name
  }
}

resource "azurerm_container_registry" "vllm" {
  name                          = local.container_registry_name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  sku                           = var.registry_sku
  admin_enabled                 = true # Required for az acr build/import provisioners. Assess against hub Azure Policy — MI-based image pull requires removing this.
  public_network_access_enabled = true # Required for az acr build context push and import from Docker Hub. Private ACR requires a self-hosted build agent with VNet access.
  tags                          = var.common_tags

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "null_resource" "enable_acr_arm_authentication" {
  triggers = {
    registry_name = azurerm_container_registry.vllm.name
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command = join("\n", [
      "set -euo pipefail",
      "",
      "status=$(az acr config authentication-as-arm show --registry ${self.triggers.registry_name} --query status --output tsv --only-show-errors 2>/dev/null || echo disabled)",
      "",
      "if [ \"$status\" != \"enabled\" ]; then",
      "  az acr config authentication-as-arm update --registry ${self.triggers.registry_name} --status enabled --only-show-errors >/dev/null",
      "fi",
    ])
  }

  depends_on = [azurerm_container_registry.vllm]
}

resource "null_resource" "import_vllm_image" {
  count = local.use_gemma4_compat_image ? 0 : 1

  triggers = {
    registry_name = azurerm_container_registry.vllm.name
    source_image  = local.source_image
    target_image  = local.repository_and_tag
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command = join("\n", [
      "set -euo pipefail",
      "",
      "if az acr repository show --name ${self.triggers.registry_name} --image ${self.triggers.target_image} --only-show-errors >/dev/null 2>&1; then",
      "  exit 0",
      "fi",
      "",
      "az acr import --name ${self.triggers.registry_name} --source ${self.triggers.source_image} --image ${self.triggers.target_image} --force --only-show-errors >/dev/null",
    ])
  }

  depends_on = [null_resource.enable_acr_arm_authentication]
}

resource "null_resource" "build_gemma4_image" {
  count = local.use_gemma4_compat_image ? 1 : 0

  triggers = {
    registry_name   = azurerm_container_registry.vllm.name
    source_image    = local.source_image
    target_image    = local.effective_repository_and_tag
    dockerfile_hash = filemd5("${path.module}/Dockerfile.gemma4")
    proxy_hash      = filemd5("${path.module}/aca_proxy.py")
    context_path    = local.module_dir
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command = join("\n", [
      "set -euo pipefail",
      "",
      "cd '${self.triggers.context_path}'",
      "az acr build --registry ${self.triggers.registry_name} --image ${self.triggers.target_image} --build-arg VLLM_BASE_IMAGE=${self.triggers.source_image} --file Dockerfile.gemma4 . --no-logs --output none --only-show-errors",
    ])
  }

  depends_on = [azurerm_container_registry.vllm]
}

resource "azurerm_storage_account" "model_cache" {
  name                            = local.model_cache_storage_name
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  public_network_access_enabled   = true
  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  tags                            = var.common_tags

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "azurerm_storage_share" "model_cache" {
  name               = local.model_cache_share_name
  storage_account_id = azurerm_storage_account.model_cache.id
  quota              = var.model_cache_share_quota_gb
}

resource "azurerm_container_app_environment" "vllm" {
  name                               = local.container_app_environment_name
  location                           = var.location
  resource_group_name                = var.resource_group_name
  log_analytics_workspace_id         = var.log_analytics_workspace_id
  logs_destination                   = "log-analytics"
  infrastructure_subnet_id           = var.infrastructure_subnet_id
  infrastructure_resource_group_name = local.infrastructure_rg_name
  internal_load_balancer_enabled     = false
  public_network_access              = "Disabled"
  mutual_tls_enabled                 = false
  zone_redundancy_enabled            = false

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }

  tags = var.common_tags

  lifecycle {
    ignore_changes = [
      tags,
      workload_profile,
    ]
  }

  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }
}

resource "azurerm_container_app_environment_storage" "model_cache" {
  name                         = local.environment_storage_name
  container_app_environment_id = azurerm_container_app_environment.vllm.id
  account_name                 = azurerm_storage_account.model_cache.name
  share_name                   = azurerm_storage_share.model_cache.name
  access_key                   = azurerm_storage_account.model_cache.primary_access_key
  access_mode                  = "ReadWrite"
}

resource "azurerm_private_endpoint" "vllm_environment" {
  name                = "${local.container_app_environment_name}-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "${local.container_app_environment_name}-psc"
    private_connection_resource_id = azurerm_container_app_environment.vllm.id
    subresource_names              = ["managedEnvironments"]
    is_manual_connection           = false
  }

  tags = var.common_tags

  lifecycle {
    ignore_changes = [
      private_dns_zone_group,
      tags,
    ]
  }
}

resource "null_resource" "wait_for_dns" {
  count = var.wait_for_private_endpoint_dns_zone_group ? 1 : 0

  triggers = {
    private_endpoint_id   = azurerm_private_endpoint.vllm_environment.id
    resource_group_name   = var.resource_group_name
    private_endpoint_name = azurerm_private_endpoint.vllm_environment.name
    timeout               = var.private_endpoint_dns_wait.timeout
    interval              = var.private_endpoint_dns_wait.poll_interval
    scripts_dir           = var.scripts_dir
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command = join("\n", [
      "${self.triggers.scripts_dir}/wait-for-dns-zone.sh --resource-group ${self.triggers.resource_group_name} --private-endpoint-name ${self.triggers.private_endpoint_name} --timeout ${self.triggers.timeout} --interval ${self.triggers.interval}",
    ])
  }

  depends_on = [azurerm_private_endpoint.vllm_environment]
}

resource "null_resource" "gpu_workload_profile" {
  triggers = {
    environment_name      = azurerm_container_app_environment.vllm.name
    resource_group_name   = var.resource_group_name
    workload_profile_name = var.workload_profile_name
    workload_profile_type = var.workload_profile_type
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command = join("\n", [
      "set -euo pipefail",
      "",
      "if az containerapp env workload-profile show --resource-group ${self.triggers.resource_group_name} --name ${self.triggers.environment_name} --workload-profile-name ${self.triggers.workload_profile_name} --only-show-errors >/dev/null 2>&1; then",
      "  exit 0",
      "fi",
      "",
      "az containerapp env workload-profile add --resource-group ${self.triggers.resource_group_name} --name ${self.triggers.environment_name} --workload-profile-name ${self.triggers.workload_profile_name} --workload-profile-type ${self.triggers.workload_profile_type} --only-show-errors >/dev/null",
    ])
  }

  depends_on = [azurerm_container_app_environment.vllm]
}

resource "azurerm_monitor_diagnostic_setting" "vllm_environment" {
  name                       = "${local.container_app_environment_name}-diagnostics"
  target_resource_id         = azurerm_container_app_environment.vllm.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "ContainerAppConsoleLogs"
  }

  enabled_log {
    category = "ContainerAppSystemLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_container_app" "vllm" {
  name                         = local.container_app_name
  resource_group_name          = var.resource_group_name
  container_app_environment_id = azurerm_container_app_environment.vllm.id
  revision_mode                = "Single"
  workload_profile_name        = var.workload_profile_name

  registry {
    server               = azurerm_container_registry.vllm.login_server
    username             = azurerm_container_registry.vllm.admin_username
    password_secret_name = "acr-admin-password"
  }

  secret {
    name  = "acr-admin-password"
    value = azurerm_container_registry.vllm.admin_password
  }

  dynamic "secret" {
    for_each = !var.offline_mode && var.huggingface_token != "" ? [var.huggingface_token] : []

    content {
      name  = "huggingface-token"
      value = secret.value
    }
  }

  ingress {
    allow_insecure_connections = false
    external_enabled           = true
    target_port                = local.vllm_service_port
    transport                  = "http"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas                = var.min_replicas
    max_replicas                = var.max_replicas
    cooldown_period_in_seconds  = 1800
    polling_interval_in_seconds = 15

    http_scale_rule {
      name                = "http-concurrency"
      concurrent_requests = "1"
    }

    container {
      name    = "vllm"
      image   = local.mirrored_image
      cpu     = local.workload_profile_resources[var.workload_profile_type].cpu
      memory  = local.workload_profile_resources[var.workload_profile_type].memory
      command = local.vllm_container_command

      args = concat(
        [
          var.model_id,
          "--host",
          local.vllm_backend_host,
          "--port",
          tostring(local.vllm_backend_port),
          "--max-model-len",
          tostring(var.max_model_len),
          "--gpu-memory-utilization",
          tostring(var.gpu_memory_utilization),
        ],
        # Append --quantization only when a backend is explicitly set. Requires a matching
        # pre-quantized HuggingFace model repo — vLLM does not quantize BF16 weights on the fly.
        var.quantization != null ? ["--quantization", var.quantization] : []
      )

      env {
        name  = "XDG_CACHE_HOME"
        value = local.model_cache_root
      }

      env {
        name  = "HF_HOME"
        value = local.huggingface_home
      }

      env {
        name  = "HF_HUB_CACHE"
        value = local.huggingface_hub_path
      }

      dynamic "env" {
        for_each = var.offline_mode ? {
          HF_HUB_OFFLINE       = "1"
          TRANSFORMERS_OFFLINE = "1"
        } : {}

        content {
          name  = env.key
          value = env.value
        }
      }

      env {
        name  = "HF_HUB_DISABLE_SYMLINKS_WARNING"
        value = "1"
      }

      env {
        name  = "VLLM_NO_USAGE_STATS"
        value = "1"
      }

      dynamic "env" {
        for_each = local.compat_image_hash == null ? [] : [local.compat_image_hash]

        content {
          name  = "GEMMA4_COMPAT_IMAGE_HASH"
          value = env.value
        }
      }

      dynamic "env" {
        for_each = !var.offline_mode && var.huggingface_token != "" ? [1] : []

        content {
          name        = "HF_TOKEN"
          secret_name = "huggingface-token"
        }
      }

      volume_mounts {
        name = "model-cache"
        path = local.model_cache_root
      }

      startup_probe {
        path                    = "/v1/models"
        port                    = local.vllm_service_port
        transport               = "HTTP"
        initial_delay           = 30
        interval_seconds        = 30
        failure_count_threshold = 120
      }

      readiness_probe {
        path                    = "/v1/models"
        port                    = local.vllm_service_port
        transport               = "HTTP"
        initial_delay           = 15
        interval_seconds        = 15
        success_count_threshold = 1
      }

      liveness_probe {
        path                    = "/v1/models"
        port                    = local.vllm_service_port
        transport               = "HTTP"
        initial_delay           = 60
        interval_seconds        = 30
        failure_count_threshold = 3
      }
    }

    volume {
      name         = "model-cache"
      storage_name = azurerm_container_app_environment_storage.model_cache.name
      storage_type = "AzureFile"
    }
  }

  tags = var.common_tags

  lifecycle {
    ignore_changes = [tags]
  }

  depends_on = [
    azurerm_container_app_environment_storage.model_cache,
    null_resource.gpu_workload_profile,
    null_resource.build_gemma4_image,
    null_resource.import_vllm_image,
    azurerm_monitor_diagnostic_setting.vllm_environment,
  ]

  timeouts {
    create = "90m"
    update = "90m"
    delete = "90m"
  }
}

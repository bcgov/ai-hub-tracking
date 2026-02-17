# =============================================================================
# DNS Zone Module
# =============================================================================
# Creates:
#   1. Resource Group for DNS resources (separate from Terraform infra RG)
#   2. Public DNS Zone for the vanity domain
#   3. Static Public IP for App Gateway (Standard SKU, zone-redundant)
#   4. A record pointing the domain apex (@) to the static PIP
#
# All resources have lifecycle { prevent_destroy = true } because:
#   - DNS Zone NS records are delegated once and must never change
#   - Static PIP is referenced by App Gateway and DNS A record
#   - Destroying these would cause production downtime
#
# The static PIP resource ID is passed to the App Gateway module so it
# uses this IP instead of auto-creating one. This means terraform destroy
# on the App Gateway does NOT affect DNS — the PIP and zone persist.
# =============================================================================

# -----------------------------------------------------------------------------
# Resource Group (dedicated for DNS, separate from main infra RG)
# -----------------------------------------------------------------------------
resource "azurerm_resource_group" "dns" {
  name     = var.resource_group_name
  location = var.location

  tags = merge(var.tags, {
    purpose    = "dns-management"
    managed-by = "terraform"
  })

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [tags]
  }
}

# -----------------------------------------------------------------------------
# Public DNS Zone
# -----------------------------------------------------------------------------
resource "azurerm_dns_zone" "this" {
  name                = var.dns_zone_name
  resource_group_name = azurerm_resource_group.dns.name

  tags = merge(var.tags, {
    purpose = "vanity-domain"
  })

  lifecycle {
    prevent_destroy = true
  }
}

# -----------------------------------------------------------------------------
# Static Public IP for App Gateway
# Standard SKU + Static allocation required for WAF_v2 App Gateway
# Zone-redundant (zones 1,2,3) for high availability
# -----------------------------------------------------------------------------
resource "azurerm_public_ip" "appgw" {
  name                = "${var.name_prefix}-appgw-pip"
  resource_group_name = azurerm_resource_group.dns.name
  location            = var.location

  sku               = "Standard"
  allocation_method = "Static"
  zones             = ["1", "2", "3"]

  domain_name_label = var.name_prefix

  # DDoS IP Protection: per-IP adaptive L3/L4 DDoS mitigation
  # Provides attack telemetry, alerting, and cost protection beyond Azure Basic
  ddos_protection_mode = var.ddos_protection_enabled ? "Enabled" : "VirtualNetworkInherited"

  tags = merge(var.tags, {
    purpose = "appgw-static-pip"
  })

  lifecycle {
    prevent_destroy = true
  }
}

# -----------------------------------------------------------------------------
# DNS A Record: apex (@) → Static PIP
# Points the vanity domain to the App Gateway's static public IP
# -----------------------------------------------------------------------------
resource "azurerm_dns_a_record" "apex" {
  name                = "@"
  zone_name           = azurerm_dns_zone.this.name
  resource_group_name = azurerm_resource_group.dns.name
  ttl                 = var.a_record_ttl
  records             = [azurerm_public_ip.appgw.ip_address]
}

# =============================================================================
# DIAGNOSTIC SETTINGS
# =============================================================================
# Always-on diagnostics for the public IP and DNS zone.
# PIP diagnostics capture DDoS protection notifications, mitigation flow logs,
# and mitigation reports — critical for attack visibility.
# DNS zone diagnostics capture query logs for security monitoring.
# =============================================================================

# -----------------------------------------------------------------------------
# Public IP Diagnostic Settings
# Captures DDoS telemetry + all metrics (packets/bytes in/dropped)
# -----------------------------------------------------------------------------
resource "azurerm_monitor_diagnostic_setting" "pip" {
  name                       = "${var.name_prefix}-pip-diag"
  target_resource_id         = azurerm_public_ip.appgw.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "DDoSProtectionNotifications"
  }

  enabled_log {
    category = "DDoSMitigationFlowLogs"
  }

  enabled_log {
    category = "DDoSMitigationReports"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

# -----------------------------------------------------------------------------
# DNS Zone Diagnostic Settings
# Captures DNS query logs for security monitoring and audit
# -----------------------------------------------------------------------------
resource "azurerm_monitor_diagnostic_setting" "dns_zone" {
  name                       = "${var.name_prefix}-dns-diag"
  target_resource_id         = azurerm_dns_zone.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "AuditEvent"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

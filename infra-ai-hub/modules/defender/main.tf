# Microsoft Defender for Cloud Subscription Pricing
#
# This module configures Microsoft Defender for Cloud pricing tiers at the
# subscription level. Each resource type is configured independently.
#
# IMPORTANT: This resource is idempotent - it will update existing pricing
# configurations rather than fail if they already exist.

resource "azurerm_security_center_subscription_pricing" "this" {
  for_each = var.resource_types

  tier          = "Standard"
  resource_type = each.key
  subplan       = each.value.subplan

  lifecycle {
    # Prevent recreation if the resource already exists
    create_before_destroy = true
  }
}

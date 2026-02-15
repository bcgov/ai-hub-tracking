locals {
  apim_config  = var.shared_config.apim
  appgw_config = var.shared_config.app_gateway
  dns_zone_config = lookup(var.shared_config, "dns_zone", {
    enabled             = false
    zone_name           = ""
    resource_group_name = ""
    a_record_ttl        = 3600
  })

  apim_gateway_fqdn = "${var.app_name}-${var.app_env}-apim.azure-api.net"
}

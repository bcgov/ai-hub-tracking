locals {
  frontend_ip_config_name  = "${var.name}-feip"
  frontend_port_https_name = "${var.name}-feport-https"
  frontend_port_http_name  = "${var.name}-feport-http"
  backend_pool_name        = "${var.name}-bepool-apim"
  http_setting_name        = "${var.name}-httpsetting"
  listener_https_name      = "${var.name}-listener-https"
  listener_http_name       = "${var.name}-listener-http"
  probe_name               = "${var.name}-probe-apim"
  redirect_config_name     = "${var.name}-redirect-https"
  routing_rule_https_name  = "${var.name}-rule-https"
  routing_rule_http_name   = "${var.name}-rule-http"

  # Get first SSL cert name for HTTPS listener
  ssl_cert_name = length(var.ssl_certificates) > 0 ? values(var.ssl_certificates)[0].name : null

  # Determine if we need managed identity for Key Vault SSL certs
  needs_identity = length(var.ssl_certificates) > 0

  # Enforced TLS policy per Landing Zone policy
  ssl_policy = {
    policy_type = "Predefined"
    policy_name = "AppGwSslPolicy20220101S"
  }
}

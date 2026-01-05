output "proxy_url" {
  description = "The URL of the Azure Proxy App Service"
  value       = azurerm_linux_web_app.azure_proxy.default_hostname
}

output "proxy_auth" {
  description = "The authentication string for the Azure Proxy"
  value       = "${random_password.proxy_chisel_username.result}:${random_password.proxy_chisel_password.result}"
  sensitive   = true
}

# Calculate subnet CIDRs based on VNet address space
locals {
  # Split the address space
  vnet_ip_base                   = split("/", var.vnet_address_space)[0]
  octets                         = split(".", local.vnet_ip_base)
  base_ip                        = "${local.octets[0]}.${local.octets[1]}.${local.octets[2]}"
  private_endpoints_subnet_cidr  = "${local.base_ip}.0/27"   # For Private Endpoints. 5 Reserved by Azure. 27 usable IPs
  app_service_subnet_cidr        = "${local.base_ip}.32/27"  # For App Service. 5 Reserved by Azure. 27 usable IPs
  container_apps_subnet_cidr     = "${local.base_ip}.64/27"  # For Container Apps Environment. 5 Reserved by Azure. 27 usable IPs
  apim_subnet_cidr               = "${local.base_ip}.96/27"  # For API Management. 5 Reserved by Azure. 27 usable IPs
  container_instance_subnet_cidr = "${local.base_ip}.128/28" # For Container Instances. 5 Reserved by Azure. 11 usable IPs
  # NOTE: the jumpbox (.144/28) and Azure Bastion (.192/26) ranges are now owned by the
  # bcgov/action-deployer-vm-bastion-alz action (tools subscription), not this module.
}

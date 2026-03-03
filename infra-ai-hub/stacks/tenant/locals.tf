locals {
  enabled_tenants = {
    for key, config in var.tenants : key => config
    if try(config.enabled, false)
  }

  # ---------------------------------------------------------------------------
  # PE subnet resolution per tenant
  # pe_subnet_key is MANDATORY for every enabled tenant (validated in variables.tf).
  # Resolution is strict by design:
  #   - Uses explicit pe_subnet_key only.
  #   - Invalid/missing key in the shared PE pool fails at plan time.
  # ---------------------------------------------------------------------------
  pe_subnet_ids_by_key = data.terraform_remote_state.shared.outputs.private_endpoint_subnet_ids_by_key

  resolved_pe_subnet_id = {
    for key, config in local.enabled_tenants : key => local.pe_subnet_ids_by_key[config.pe_subnet_key]
  }
}

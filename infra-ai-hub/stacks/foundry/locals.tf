locals {
  enabled_tenants = {
    for key, config in var.tenants : key => config
    if try(config.enabled, false)
  }

  # Maps a model name prefix (lowercase) to its API format string.
  # Used to derive the model format from the deployment model_name without
  # requiring a model_format attribute in every tenant tfvars entry (which
  # would break Terraform's map(any) type unification across tenants).
  # Add new entries here when onboarding models from additional providers.
  model_format_prefixes = {
    "cohere" = "Cohere"
    # "mistral" = "MistralAI"  # example for future providers
  }

  # Derives default format = "OpenAI" unless the lowercased model name starts
  # with a known vendor prefix.
  default_model_format = "OpenAI"
}

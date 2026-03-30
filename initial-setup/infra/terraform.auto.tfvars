# -----------------------------------------------------------------------------
# Terraform Variables Configuration
# -----------------------------------------------------------------------------

# Application Configuration
app_env  = "tools"
app_name = "ai-hub"

# Azure Resource Configuration
location            = "Canada Central"
resource_group_name = "ai-hub-tools"

# Common Tags
common_tags = {
  environment = "tools"
  app_env     = "tools"
  repo_name   = "ai-hub-tracking"
  project     = "ai-hub"
  managed_by  = "Terraform"
}




# -----------------------------------------------------------------------------
# GitHub Runners on Azure Container Apps
# -----------------------------------------------------------------------------
# These are set via TF_VAR_* environment variables in GitHub Actions
github_runners_aca_enabled = false             # Enable in GitHub Actions workflow
github_organization        = "bcgov"           # Set via TF_VAR_github_organization
github_repository          = "ai-hub-tracking" # Set via TF_VAR_github_repository



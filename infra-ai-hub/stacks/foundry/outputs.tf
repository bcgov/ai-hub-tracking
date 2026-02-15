output "tenant_projects" {
  value = {
    for tenant_key, project in module.foundry_project : tenant_key => {
      project_id           = project.project_id
      project_name         = project.project_name
      project_principal_id = project.project_principal_id
      deployment_ids       = project.ai_model_deployment_ids
      deployment_names     = project.ai_model_deployment_names
      deployment_mapping   = project.ai_model_deployment_mapping
      has_deployments      = project.has_model_deployments
    }
  }
}

output "tenant_ai_model_deployments" {
  value = {
    for project_key, project in module.foundry_project : project_key => {
      deployment_ids     = project.ai_model_deployment_ids
      deployment_names   = project.ai_model_deployment_names
      deployment_mapping = project.ai_model_deployment_mapping
      has_deployments    = project.has_model_deployments
    } if project.has_model_deployments
  }
}

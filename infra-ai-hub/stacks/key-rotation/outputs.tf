output "key_rotation_job" {
  description = "Key rotation Container App Job details (null when not deployed)"
  value = length(module.key_rotation) > 0 ? {
    job_name     = module.key_rotation[0].job_name
    job_id       = module.key_rotation[0].job_id
    principal_id = module.key_rotation[0].principal_id
  } : null
}

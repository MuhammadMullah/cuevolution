output "web_service_account" {
  value = module.cuevolution.web_service_account
}

output "worker_service_account" {
  value = module.cuevolution.worker_service_account
}

output "artifact_registry" {
  value = module.cuevolution.artifact_registry
}

output "github_workload_identity_provider" {
  value = module.cuevolution.github_workload_identity_provider
}

output "github_deployer_service_account" {
  value = module.cuevolution.github_deployer_service_account
}

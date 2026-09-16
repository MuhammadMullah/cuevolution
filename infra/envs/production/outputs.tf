output "web_service_account" {
  description = "Service account of the web service and migration job."
  value       = module.cuevolution.web_service_account
}

output "worker_service_account" {
  description = "Service account of the worker Cloud Run instance."
  value       = module.cuevolution.worker_service_account
}

output "web_url" {
  description = "Default run.app URL of the web service."
  value       = module.cuevolution.web_url
}

output "migration_job_name" {
  description = "Cloud Run job that runs migrations."
  value       = module.cuevolution.migration_job_name
}

output "worker_instance_name" {
  description = "Worker Cloud Run instance name used by Cloud Build."
  value       = module.cuevolution.worker_instance_name
}

output "artifact_registry" {
  description = "Docker repository path for images."
  value       = module.cuevolution.artifact_registry
}

output "profile_pictures_bucket" {
  description = "Private bucket for player profile pictures."
  value       = module.cuevolution.profile_pictures_bucket
}

output "db_connection_name" {
  description = "Cloud SQL connection name."
  value       = module.cuevolution.db_connection_name
}

output "database_url_secret_id" {
  description = "Secret Manager secret holding DATABASE_URL."
  value       = module.cuevolution.database_url_secret_id
}

output "domain_dns_records" {
  description = "DNS records to create at Cloudflare (DNS-only) for sportpesapool.ke."
  value       = module.cuevolution.domain_dns_records
}

output "github_workload_identity_provider" {
  description = "Value for the GCP_WORKLOAD_IDENTITY_PROVIDER GitHub secret."
  value       = module.cuevolution.github_workload_identity_provider
}

output "github_deployer_service_account" {
  description = "Value for the GCP_DEPLOYER_SERVICE_ACCOUNT GitHub secret."
  value       = module.cuevolution.github_deployer_service_account
}

output "vm_service_account" {
  description = "Service account attached to the web+worker VM."
  value       = module.cuevolution.vm_service_account
}

output "vm_ip" {
  description = "Static external IP of the web+worker VM. Point DNS here at cutover; also the SSH_HOST for the deploy-vm workflow."
  value       = module.cuevolution.vm_ip
}

output "vm_database_url_secret_id" {
  description = "Secret Manager secret holding the VM's cloud-sql-proxy-shaped DATABASE_URL, fetched at deploy time."
  value       = module.cuevolution.vm_database_url_secret_id
}

output "web_service_account" {
  description = "Service account of the web service and migration job."
  value       = google_service_account.web.email
}

output "worker_service_account" {
  description = "Service account the worker Cloud Run instance runs as."
  value       = google_service_account.worker.email
}

output "web_service_name" {
  description = "Cloud Run web service name."
  value       = google_cloud_run_v2_service.web_app.name
}

output "web_url" {
  description = "Default run.app URL of the web service (smoke tests before DNS cutover)."
  value       = google_cloud_run_v2_service.web_app.uri
}

output "migration_job_name" {
  description = "Cloud Run job that runs Ecto migrations."
  value       = google_cloud_run_v2_job.db_migrate.name
}

output "worker_instance_name" {
  description = "Name Cloud Build uses for the worker Cloud Run instance (not managed by Terraform)."
  value       = "cuevolution-${var.environment}-worker"
}

output "artifact_registry" {
  description = "Docker repository path for images."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.container_images.repository_id}"
}

output "profile_pictures_bucket" {
  description = "Private bucket for player profile pictures."
  value       = google_storage_bucket.player_uploads.name
}

output "db_connection_name" {
  description = "Cloud SQL connection name (PROJECT:REGION:INSTANCE)."
  value       = google_sql_database_instance.db.connection_name
}

output "database_url_secret_id" {
  description = "Secret Manager secret holding DATABASE_URL."
  value       = google_secret_manager_secret.database_url.secret_id
}

output "domain_dns_records" {
  description = "DNS records to create at Cloudflare (DNS-only) for the mapped domain."
  value       = try(google_cloud_run_domain_mapping.apex[0].status[0].resource_records, [])
}

output "github_workload_identity_provider" {
  description = "Value for the GCP_WORKLOAD_IDENTITY_PROVIDER GitHub secret."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "github_deployer_service_account" {
  description = "Value for the GCP_DEPLOYER_SERVICE_ACCOUNT GitHub secret."
  value       = google_service_account.github_deployer.email
}

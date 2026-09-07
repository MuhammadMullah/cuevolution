output "web_service_account" {
  value = google_service_account.web.email
}

output "worker_service_account" {
  value = google_service_account.worker.email
}

output "web_service_name" {
  value = google_cloud_run_v2_service.web.name
}

output "worker_service_name" {
  value = google_cloud_run_v2_service.worker.name
}

output "migration_job_name" {
  value = google_cloud_run_v2_job.migrate.name
}

output "artifact_registry" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.images.repository_id}"
}

output "github_workload_identity_provider" {
  value = google_iam_workload_identity_pool_provider.github.name
}

output "github_deployer_service_account" {
  value = google_service_account.github_deployer.email
}

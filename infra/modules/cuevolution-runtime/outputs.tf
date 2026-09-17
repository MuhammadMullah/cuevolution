output "profile_pictures_bucket" {
  description = "Private bucket for player profile pictures."
  value       = google_storage_bucket.player_uploads.name
}

output "db_connection_name" {
  description = "Cloud SQL connection name (PROJECT:REGION:INSTANCE)."
  value       = google_sql_database_instance.db.connection_name
}

output "vm_service_account" {
  description = "Service account attached to the web+worker VM (compute.tf)."
  value       = google_service_account.vm.email
}

output "vm_ip" {
  description = "Static external IP of the web+worker VM. Point DNS here at cutover; also the SSH_HOST for the deploy-vm workflow."
  value       = google_compute_address.vm.address
}

output "vm_database_url_secret_id" {
  description = "Secret Manager secret holding the VM's cloud-sql-proxy-shaped DATABASE_URL, fetched at deploy time (see app/deploy/README.md)."
  value       = google_secret_manager_secret.vm_database_url.secret_id
}

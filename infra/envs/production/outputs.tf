output "profile_pictures_bucket" {
  description = "Private bucket for player profile pictures."
  value       = module.cuevolution.profile_pictures_bucket
}

output "db_connection_name" {
  description = "Cloud SQL connection name."
  value       = module.cuevolution.db_connection_name
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

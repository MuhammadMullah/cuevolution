resource "google_secret_manager_secret" "application" {
  for_each = toset([var.application_secrets_secret_id])

  project   = var.project_id
  secret_id = each.value

  replication {
    auto {}
  }

  depends_on = [google_project_service.required["secretmanager.googleapis.com"]]
}

# The VM (compute.tf) fetches this same secret at deploy time — same content
# (SECRET_KEY_BASE, SMTP_USERNAME/PASSWORD, AFRICASTALKING_*, added out of
# band same as for web/worker), same Secret Manager entry, just read by
# `gcloud secrets versions access` over SSH instead of Cloud Run's
# --set-secrets.
resource "google_secret_manager_secret_iam_member" "vm_accessor" {
  for_each = google_secret_manager_secret.application

  project   = var.project_id
  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.vm.email}"
}

# The VM connects through cloud-sql-proxy over TCP rather than a /cloudsql
# socket mount, so it needs the same credentials (same var.db_user, same
# generated ephemeral.random_password.db) in a differently-shaped URL.
# Terraform-written, not a hand copy-paste — deploy.sh fetches this at
# deploy time via `gcloud secrets versions access`.
resource "google_secret_manager_secret" "vm_database_url" {
  project   = var.project_id
  secret_id = "cuevolution-${var.environment}-vm-database-url"

  replication {
    auto {}
  }

  depends_on = [google_project_service.required["secretmanager.googleapis.com"]]
}

resource "google_secret_manager_secret_version" "vm_database_url" {
  secret                 = google_secret_manager_secret.vm_database_url.id
  secret_data_wo         = "ecto://${var.db_user}:${ephemeral.random_password.db.result}@cloud-sql-proxy:5432/${var.db_name}"
  secret_data_wo_version = var.db_password_version
}

resource "google_secret_manager_secret_iam_member" "vm_database_url_accessor" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.vm_database_url.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.vm.email}"
}

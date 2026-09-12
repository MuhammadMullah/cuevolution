resource "google_secret_manager_secret" "application" {
  for_each = toset([var.application_secrets_secret_id])

  project   = var.project_id
  secret_id = each.value

  replication {
    auto {}
  }

  depends_on = [google_project_service.required["secretmanager.googleapis.com"]]
}

resource "google_secret_manager_secret_iam_member" "web_accessor" {
  for_each = google_secret_manager_secret.application

  project   = var.project_id
  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.web.email}"
}

resource "google_secret_manager_secret_iam_member" "worker_accessor" {
  for_each = google_secret_manager_secret.application

  project   = var.project_id
  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.worker.email}"
}

# DATABASE_URL lives in its own Terraform-written secret. The app prefers a
# plain DATABASE_URL over the key inside CUEVOLUTION_SECRETS_JSON.
resource "google_secret_manager_secret" "database_url" {
  project   = var.project_id
  secret_id = "cuevolution-${var.environment}-database-url"

  replication {
    auto {}
  }

  depends_on = [google_project_service.required["secretmanager.googleapis.com"]]
}

resource "google_secret_manager_secret_version" "database_url" {
  secret                 = google_secret_manager_secret.database_url.id
  secret_data_wo         = "ecto://${var.db_user}:${ephemeral.random_password.db.result}@localhost/${var.db_name}?socket_dir=/cloudsql/${google_sql_database_instance.db.connection_name}"
  secret_data_wo_version = var.db_password_version
}

resource "google_secret_manager_secret_iam_member" "web_database_url_accessor" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.database_url.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.web.email}"
}

resource "google_secret_manager_secret_iam_member" "worker_database_url_accessor" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.database_url.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.worker.email}"
}

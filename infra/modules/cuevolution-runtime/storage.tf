resource "google_artifact_registry_repository" "container_images" {
  project       = var.project_id
  location      = var.region
  repository_id = "cuevolution-images"
  description   = "Cuevolution container images for ${var.environment}"
  format        = "DOCKER"

  # Every commit pushes an image; keep the 10 newest for rollback and delete
  # anything older than 30 days. KEEP rules win over DELETE rules.
  cleanup_policy_dry_run = false

  cleanup_policies {
    id     = "keep-recent-releases"
    action = "KEEP"

    most_recent_versions {
      keep_count = 10
    }
  }

  cleanup_policies {
    id     = "delete-older-than-30-days"
    action = "DELETE"

    condition {
      tag_state  = "ANY"
      older_than = "2592000s"
    }
  }

  depends_on = [google_project_service.required["artifactregistry.googleapis.com"]]
}

resource "google_storage_bucket" "player_uploads" {
  project                     = var.project_id
  name                        = var.profile_pictures_bucket
  location                    = var.region
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  depends_on = [google_project_service.required["storage.googleapis.com"]]
}

resource "google_storage_bucket_iam_member" "web_uploads_object_user" {
  bucket = google_storage_bucket.player_uploads.name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.web.email}"
}

resource "google_storage_bucket_iam_member" "worker_uploads_object_user" {
  bucket = google_storage_bucket.player_uploads.name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.worker.email}"
}

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

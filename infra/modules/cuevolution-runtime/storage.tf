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

# Admin-uploaded scans/photos of venue result sheets (spec 012) — kept for
# future reference only, never read back by the app's qualification logic.
# Separate bucket from player_uploads so the two lifecycles (player-facing
# avatars vs. admin-only paperwork) can be managed/retained independently.
resource "google_storage_bucket" "result_sheets" {
  project                     = var.project_id
  name                        = var.result_sheets_bucket
  location                    = var.region
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  depends_on = [google_project_service.required["storage.googleapis.com"]]
}

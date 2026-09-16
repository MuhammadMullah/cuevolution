# Flat-rate compute alternative to the Cloud Run web/worker services in
# run.tf. One VM runs both the Phoenix web and Oban worker containers (see
# app/deploy/), so it gets a single service account rather than the separate
# web/worker split Cloud Run uses. Cloud Run resources are left untouched so
# production keeps serving traffic while this is provisioned and verified;
# see infra/README.md for the cutover/decommission sequence.

resource "google_service_account" "vm" {
  project      = var.project_id
  account_id   = "cuevolution-${var.environment}-vm"
  display_name = "Cuevolution ${var.environment} VM (web + worker)"
}

resource "google_storage_bucket_iam_member" "vm_uploads_object_user" {
  bucket = google_storage_bucket.player_uploads.name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.vm.email}"
}

resource "google_project_iam_member" "vm_cloud_sql" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.vm.email}"
}

# Self token-creator lets the VM's identity sign V4 URLs for private GCS
# objects, same as web_signer/worker_signer in iam.tf.
resource "google_service_account_iam_member" "vm_signer" {
  service_account_id = google_service_account.vm.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${google_service_account.vm.email}"
}

resource "google_compute_address" "vm" {
  project = var.project_id
  region  = var.region
  name    = "cuevolution-${var.environment}-vm"
}

resource "google_compute_firewall" "allow_web" {
  project       = var.project_id
  name          = "cuevolution-${var.environment}-allow-web"
  network       = "default"
  direction     = "INGRESS"
  target_tags   = ["cuevolution-${var.environment}-vm"]
  source_ranges = ["0.0.0.0/0"]

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  depends_on = [google_project_service.required["compute.googleapis.com"]]
}

resource "google_compute_firewall" "allow_ssh" {
  project       = var.project_id
  name          = "cuevolution-${var.environment}-allow-ssh"
  network       = "default"
  direction     = "INGRESS"
  target_tags   = ["cuevolution-${var.environment}-vm"]
  source_ranges = var.ssh_allowed_cidrs

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  depends_on = [google_project_service.required["compute.googleapis.com"]]
}

resource "google_compute_instance" "app" {
  project      = var.project_id
  name         = "cuevolution-${var.environment}-vm"
  zone         = coalesce(var.vm_zone, "${var.region}-a")
  machine_type = var.vm_machine_type
  tags         = ["cuevolution-${var.environment}-vm"]

  # Deleting the instance loses nothing stateful (the app is stateless
  # containers; data lives in Cloud SQL/GCS), but require an explicit
  # override so `terraform destroy`/an errant apply can't take production down
  # silently.
  deletion_protection = true

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 20
      type  = "pd-balanced"
    }
  }

  network_interface {
    network = "default"

    access_config {
      nat_ip = google_compute_address.vm.address
    }
  }

  service_account {
    email  = google_service_account.vm.email
    scopes = ["cloud-platform"]
  }

  # Installs Docker Engine + the compose plugin, and the gcloud CLI, on first
  # boot so the only manual setup left is copying app/deploy/*'s compose
  # files and writing .env (see app/deploy/README.md). gcloud needs no
  # explicit login here: it picks up this VM's attached service account
  # automatically, the same way cloud-sql-proxy and the GCS requester do —
  # it's what lets the deploy script fetch DATABASE_URL/
  # CUEVOLUTION_SECRETS_JSON straight from Secret Manager on every deploy
  # instead of a hand copy-paste into .env.
  metadata_startup_script = <<-EOT
    #!/bin/bash
    set -euo pipefail

    if ! command -v docker >/dev/null 2>&1; then
      apt-get update
      apt-get install -y ca-certificates curl
      install -m 0755 -d /etc/apt/keyrings
      curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
      chmod a+r /etc/apt/keyrings/docker.asc
      echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        > /etc/apt/sources.list.d/docker.list
      apt-get update
      apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi

    if ! command -v gcloud >/dev/null 2>&1; then
      apt-get update
      apt-get install -y apt-transport-https ca-certificates gnupg curl
      install -m 0755 -d /usr/share/keyrings
      curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
        | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
      echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
        > /etc/apt/sources.list.d/google-cloud-sdk.list
      apt-get update
      apt-get install -y google-cloud-cli
    fi
  EOT

  depends_on = [
    google_project_service.required["compute.googleapis.com"],
    google_org_policy_policy.allow_vm_external_ip,
  ]
}

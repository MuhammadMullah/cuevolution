resource "google_project_service" "required" {
  for_each = toset([
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "secretmanager.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "storage.googleapis.com"
  ])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

data "google_project" "current" {
  project_id = var.project_id
}

resource "google_artifact_registry_repository" "images" {
  project       = var.project_id
  location      = var.region
  repository_id = "cuevolution-images"
  description   = "Cuevolution container images for ${var.environment}"
  format        = "DOCKER"

  depends_on = [google_project_service.required]
}

resource "google_service_account" "web" {
  project      = var.project_id
  account_id   = "cuevolution-${var.environment}-web"
  display_name = "Cuevolution ${var.environment} Cloud Run web"
}

resource "google_service_account" "worker" {
  project      = var.project_id
  account_id   = "cuevolution-${var.environment}-worker"
  display_name = "Cuevolution ${var.environment} Oban worker"
}

resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = "cuevolution-github"
  display_name              = "Cuevolution GitHub Actions"
  description               = "Keyless deployment identity for ${var.environment}"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github"
  display_name                       = "GitHub Actions OIDC"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
  }

  attribute_condition = "assertion.repository == '${var.github_repository}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account" "github_deployer" {
  project      = var.project_id
  account_id   = "cuevolution-${var.environment}-deployer"
  display_name = "Cuevolution ${var.environment} GitHub deployer"
}

resource "google_service_account" "cloud_build" {
  project      = var.project_id
  account_id   = "cuevolution-${var.environment}-cb"
  display_name = "Cuevolution ${var.environment} Cloud Build"
}

resource "google_project_iam_member" "github_artifact_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.github_deployer.email}"
}

resource "google_project_iam_member" "github_run_admin" {
  project = var.project_id
  role    = "roles/run.admin"
  member  = "serviceAccount:${google_service_account.github_deployer.email}"
}

resource "google_project_iam_member" "github_cloud_build_submitter" {
  project = var.project_id
  role    = "roles/cloudbuild.builds.editor"
  member  = "serviceAccount:${google_service_account.github_deployer.email}"
}

resource "google_project_iam_member" "github_project_viewer" {
  project = var.project_id
  role    = "roles/viewer"
  member  = "serviceAccount:${google_service_account.github_deployer.email}"
}

resource "google_storage_bucket_iam_member" "github_cloud_build_source_uploader" {
  bucket = "${var.project_id}_cloudbuild"
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.github_deployer.email}"
}

resource "google_project_iam_member" "github_service_usage_consumer" {
  project = var.project_id
  role    = "roles/serviceusage.serviceUsageConsumer"
  member  = "serviceAccount:${google_service_account.github_deployer.email}"
}

# `gcloud builds submit` uploads the local source tarball as the invoking
# principal, not the Cloud Build service account. The auto-created default
# staging bucket (`<project>_cloudbuild`) grants access via legacy bucket
# ACLs to project editors/owners only, which the least-privilege deployer
# service account is not, so uploads are forbidden. Manage an explicit
# staging bucket instead and grant the deployer object access on it.
resource "google_storage_bucket" "cloudbuild_source" {
  project                     = var.project_id
  name                        = "${var.project_id}-cloudbuild-source"
  location                    = var.region
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true

  lifecycle_rule {
    condition {
      age = 7
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_project_service.required["storage.googleapis.com"]]
}

resource "google_storage_bucket_iam_member" "github_cloudbuild_source_object_user" {
  bucket = google_storage_bucket.cloudbuild_source.name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.github_deployer.email}"
}

resource "google_storage_bucket_iam_member" "cloud_build_agent_source_object_viewer" {
  bucket = google_storage_bucket.cloudbuild_source.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-cloudbuild.iam.gserviceaccount.com"

  depends_on = [google_project_service.required["cloudbuild.googleapis.com"]]
}

resource "google_project_iam_member" "cloud_build_service_agent" {
  project = var.project_id
  role    = "roles/cloudbuild.serviceAgent"
  member  = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-cloudbuild.iam.gserviceaccount.com"

  depends_on = [google_project_service.required["cloudbuild.googleapis.com"]]
}

resource "google_project_iam_member" "cloud_build_service_usage_consumer" {
  project = var.project_id
  role    = "roles/serviceusage.serviceUsageConsumer"
  member  = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-cloudbuild.iam.gserviceaccount.com"

  depends_on = [google_project_service.required["cloudbuild.googleapis.com"]]
}

resource "google_project_iam_member" "cloud_build_artifact_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.cloud_build.email}"
}

resource "google_project_iam_member" "cloud_build_run_admin" {
  project = var.project_id
  role    = "roles/run.admin"
  member  = "serviceAccount:${google_service_account.cloud_build.email}"
}

resource "google_project_iam_member" "cloud_build_builder" {
  project = var.project_id
  role    = "roles/cloudbuild.builds.builder"
  member  = "serviceAccount:${google_service_account.cloud_build.email}"
}

resource "google_project_iam_member" "cloud_build_logs_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloud_build.email}"
}

resource "google_service_account_iam_member" "github_web_act_as" {
  service_account_id = google_service_account.web.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.github_deployer.email}"
}

resource "google_service_account_iam_member" "github_worker_act_as" {
  service_account_id = google_service_account.worker.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.github_deployer.email}"
}

resource "google_service_account_iam_member" "cloud_build_web_act_as" {
  service_account_id = google_service_account.web.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.cloud_build.email}"
}

resource "google_service_account_iam_member" "cloud_build_worker_act_as" {
  service_account_id = google_service_account.worker.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.cloud_build.email}"
}

resource "google_service_account_iam_member" "cloud_build_self_token_creator" {
  service_account_id = google_service_account.cloud_build.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${google_service_account.cloud_build.email}"
}

resource "google_service_account_iam_member" "github_cloud_build_act_as" {
  service_account_id = google_service_account.cloud_build.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.github_deployer.email}"
}

resource "google_service_account_iam_member" "github_cloud_build_token_creator" {
  service_account_id = google_service_account.cloud_build.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${google_service_account.github_deployer.email}"
}

resource "google_service_account_iam_member" "github_wif_user" {
  service_account_id = google_service_account.github_deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repository}"
}

resource "google_service_account_iam_member" "web_signer" {
  service_account_id = google_service_account.web.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${google_service_account.web.email}"
}

resource "google_service_account_iam_member" "worker_signer" {
  service_account_id = google_service_account.worker.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${google_service_account.worker.email}"
}

resource "google_project_iam_member" "web_cloud_sql" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.web.email}"
}

resource "google_project_iam_member" "worker_cloud_sql" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.worker.email}"
}

resource "google_secret_manager_secret" "application" {
  for_each  = var.secret_ids
  project   = var.project_id
  secret_id = each.value

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_iam_member" "web_accessor" {
  for_each  = var.secret_ids
  project   = var.project_id
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.web.email}"
}

resource "google_secret_manager_secret_iam_member" "worker_accessor" {
  for_each  = var.secret_ids
  project   = var.project_id
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.worker.email}"
}

resource "google_storage_bucket" "profile_pictures" {
  project                     = var.project_id
  name                        = var.storage_bucket
  location                    = var.region
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false
}

resource "google_storage_bucket_iam_member" "web_object_user" {
  bucket = google_storage_bucket.profile_pictures.name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.web.email}"
}

resource "google_storage_bucket_iam_member" "worker_object_user" {
  bucket = google_storage_bucket.profile_pictures.name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.worker.email}"
}

locals {
  secret_env = {
    CUEVOLUTION_SECRETS_JSON = var.application_secrets_secret_id
  }

  all_secret_env = local.secret_env
}

locals {
  common_env = {
    DB_SSL                   = "false"
    PHX_SERVER               = "true"
    CUEVOLUTION_SECRETS_FILE = "/secrets/application.json"
    PROFILE_PICTURE_STORAGE  = "gcs"
    GCS_BUCKET               = var.storage_bucket
    GCS_SIGNING_SERVICE_ACCOUNT = google_service_account.web.email
    PHX_HOST                 = var.phx_host
    MAIL_PROVIDER            = var.mail_provider
    SMS_PROVIDER             = var.sms_provider
    MAIL_FROM_ADDRESS        = var.mail_from_address
    AFRICASTALKING_SENDER_ID = var.africastalking_sender_id
    OBAN_ENABLED             = "true"
    POOL_SIZE                = "5"
  }

  web_env = merge(local.common_env, { OBAN_ENABLED = "false" })
  worker_env = merge(local.common_env, {
    GCS_SIGNING_SERVICE_ACCOUNT = google_service_account.worker.email
  })
  migration_env = merge(local.common_env, { PHX_SERVER = "false", OBAN_ENABLED = "false" })
}

resource "google_cloud_run_v2_service" "web" {
  name                = "cuevolution-${var.environment}-web"
  project             = var.project_id
  location            = var.region
  deletion_protection = true
  ingress             = "INGRESS_TRAFFIC_ALL"

  template {
    service_account                  = google_service_account.web.email
    max_instance_request_concurrency = 80

    scaling {
      min_instance_count = var.web_min_instances
      max_instance_count = var.web_max_instances
    }

    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = [var.cloud_sql_connection_name]
      }
    }

    volumes {
      name = "secrets"
      secret {
        secret = google_secret_manager_secret.application[var.application_secrets_secret_id].id
        items {
          version = "latest"
          path    = "application.json"
        }
      }
    }

    containers {
      image   = var.image
      command = ["/app/bin/cuevolution"]
      args    = ["start"]

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }

      volume_mounts {
        name       = "cloudsql"
        mount_path = "/cloudsql"
      }

      volume_mounts {
        name       = "secrets"
        mount_path = "/secrets"
      }

      dynamic "env" {
        for_each = local.web_env
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = local.all_secret_env
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = env.value
              version = "latest"
            }
          }
        }
      }
    }
  }

  depends_on = [
    google_secret_manager_secret_iam_member.web_accessor,
    google_project_iam_member.web_cloud_sql,
    google_service_account_iam_member.github_web_act_as,
    google_service_account_iam_member.web_signer,
    google_storage_bucket_iam_member.web_object_user
  ]
}

resource "google_cloud_run_v2_service_iam_member" "cloud_build_web_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.web.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.cloud_build.email}"
}

resource "google_cloud_run_v2_service" "worker" {
  name                = "cuevolution-${var.environment}-worker"
  project             = var.project_id
  location            = var.region
  deletion_protection = true
  ingress             = var.worker_ingress

  template {
    service_account                  = google_service_account.worker.email
    max_instance_request_concurrency = 80

    scaling {
      min_instance_count = var.worker_min_instances
      max_instance_count = var.worker_max_instances
    }

    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = [var.cloud_sql_connection_name]
      }
    }

    volumes {
      name = "secrets"
      secret {
        secret = google_secret_manager_secret.application[var.application_secrets_secret_id].id
        items {
          version = "latest"
          path    = "application.json"
        }
      }
    }

    containers {
      image   = var.image
      command = ["/app/bin/cuevolution"]
      args    = ["start"]

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle = false
      }

      volume_mounts {
        name       = "cloudsql"
        mount_path = "/cloudsql"
      }

      volume_mounts {
        name       = "secrets"
        mount_path = "/secrets"
      }

      dynamic "env" {
        for_each = local.worker_env
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = local.all_secret_env
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = env.value
              version = "latest"
            }
          }
        }
      }
    }
  }

  depends_on = [
    google_secret_manager_secret_iam_member.worker_accessor,
    google_project_iam_member.worker_cloud_sql,
    google_service_account_iam_member.github_worker_act_as,
    google_service_account_iam_member.worker_signer,
    google_storage_bucket_iam_member.worker_object_user
  ]
}

resource "google_cloud_run_v2_job" "migrate" {
  name     = "cuevolution-${var.environment}-migrate"
  project  = var.project_id
  location = var.region

  template {
    template {
      service_account = google_service_account.web.email

      volumes {
        name = "cloudsql"
        cloud_sql_instance {
          instances = [var.cloud_sql_connection_name]
        }
      }

      volumes {
        name = "secrets"
        secret {
          secret = google_secret_manager_secret.application[var.application_secrets_secret_id].id
          items {
            version = "latest"
            path    = "application.json"
          }
        }
      }

      containers {
        image   = var.image
        command = ["/app/bin/migrate"]

        resources {
          limits = {
            cpu    = "1"
            memory = "512Mi"
          }
        }

        volume_mounts {
          name       = "cloudsql"
          mount_path = "/cloudsql"
        }

        volume_mounts {
          name       = "secrets"
          mount_path = "/secrets"
        }

        dynamic "env" {
          for_each = local.migration_env
          content {
            name  = env.key
            value = env.value
          }
        }

        dynamic "env" {
          for_each = local.all_secret_env
          content {
            name = env.key
            value_source {
              secret_key_ref {
                secret  = env.value
                version = "latest"
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    google_secret_manager_secret_iam_member.web_accessor,
    google_project_iam_member.web_cloud_sql,
    google_storage_bucket_iam_member.web_object_user,
    google_service_account_iam_member.web_signer
  ]
}

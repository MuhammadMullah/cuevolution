locals {
  shared_env = {
    DB_SSL                   = "false"
    PROFILE_PICTURE_STORAGE  = "gcs"
    GCS_BUCKET               = google_storage_bucket.player_uploads.name
    PHX_HOST                 = var.phx_host
    MAIL_PROVIDER            = var.mail_provider
    SMS_PROVIDER             = var.sms_provider
    MAIL_FROM_ADDRESS        = var.mail_from_address
    AFRICASTALKING_SENDER_ID = var.africastalking_sender_id
  }

  # The worker Cloud Run instance copies these plain env vars from the web
  # service at deploy time (cloudbuild.yaml), overriding OBAN_QUEUES, POOL_SIZE
  # and GCS_SIGNING_SERVICE_ACCOUNT.
  web_env = merge(local.shared_env, {
    PHX_SERVER                  = "true"
    OBAN_QUEUES                 = "false"
    POOL_SIZE                   = tostring(var.web_pool_size)
    GCS_SIGNING_SERVICE_ACCOUNT = google_service_account.web.email
  })

  # PHX_SERVER is deliberately unset: runtime.exs treats any value as true.
  migrate_env = merge(local.shared_env, {
    OBAN_ENABLED                = "false"
    POOL_SIZE                   = "2"
    GCS_SIGNING_SERVICE_ACCOUNT = google_service_account.web.email
  })

  secret_env = {
    CUEVOLUTION_SECRETS_JSON = google_secret_manager_secret.application[var.application_secrets_secret_id].secret_id
    DATABASE_URL             = google_secret_manager_secret.database_url.secret_id
  }
}

resource "google_cloud_run_v2_service" "web_app" {
  name                 = "cuevolution-${var.environment}-web"
  project              = var.project_id
  location             = var.region
  deletion_protection  = true
  invoker_iam_disabled = true
  ingress              = "INGRESS_TRAFFIC_ALL"

  template {
    service_account                  = google_service_account.web.email
    max_instance_request_concurrency = 80

    scaling {
      min_instance_count = 0
      max_instance_count = var.web_max_instances
    }

    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = [google_sql_database_instance.db.connection_name]
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
        # Must be explicit when limits are set, otherwise Cloud Run switches to
        # instance-based billing (CPU always allocated).
        cpu_idle          = true
        startup_cpu_boost = true
      }

      startup_probe {
        period_seconds    = 5
        timeout_seconds   = 3
        failure_threshold = 24

        http_get {
          path = "/health/readiness"
        }
      }

      liveness_probe {
        period_seconds  = 30
        timeout_seconds = 3

        http_get {
          path = "/health/live"
        }
      }

      volume_mounts {
        name       = "cloudsql"
        mount_path = "/cloudsql"
      }

      dynamic "env" {
        for_each = local.web_env
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = local.secret_env
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
    google_project_service.required["run.googleapis.com"],
    google_secret_manager_secret_version.database_url,
    google_secret_manager_secret_iam_member.web_accessor,
    google_secret_manager_secret_iam_member.web_database_url_accessor,
    google_sql_user.app,
    google_project_iam_member.web_cloud_sql,
    google_service_account_iam_member.web_signer,
    google_storage_bucket_iam_member.web_uploads_object_user
  ]

  lifecycle {
    # Cloud Build deploys new images by digest; Terraform only sets the first one.
    ignore_changes = [template[0].containers[0].image, client, client_version]
  }
}

resource "google_cloud_run_v2_job" "db_migrate" {
  name                = "cuevolution-${var.environment}-migrate"
  project             = var.project_id
  location            = var.region
  deletion_protection = true

  template {
    template {
      service_account = google_service_account.web.email
      max_retries     = 0

      volumes {
        name = "cloudsql"
        cloud_sql_instance {
          instances = [google_sql_database_instance.db.connection_name]
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

        dynamic "env" {
          for_each = local.migrate_env
          content {
            name  = env.key
            value = env.value
          }
        }

        dynamic "env" {
          for_each = local.secret_env
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
    google_project_service.required["run.googleapis.com"],
    google_secret_manager_secret_version.database_url,
    google_secret_manager_secret_iam_member.web_accessor,
    google_secret_manager_secret_iam_member.web_database_url_accessor,
    google_sql_user.app,
    google_project_iam_member.web_cloud_sql
  ]

  lifecycle {
    ignore_changes = [template[0].template[0].containers[0].image, client, client_version]
  }
}

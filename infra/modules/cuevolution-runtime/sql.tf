resource "google_sql_database_instance" "db" {
  project             = var.project_id
  name                = "cuevolution-${var.environment}-db"
  region              = var.region
  database_version    = var.db_version
  deletion_protection = true

  settings {
    # Shared-core tiers (db-f1-micro, db-g1-small) exist only in the Enterprise
    # edition; PostgreSQL 16+ defaults to Enterprise Plus if this is omitted.
    edition                     = "ENTERPRISE"
    tier                        = var.db_tier
    availability_type           = "ZONAL"
    disk_type                   = "PD_SSD"
    disk_size                   = var.db_disk_size
    disk_autoresize             = true
    deletion_protection_enabled = true

    backup_configuration {
      enabled                        = true
      start_time                     = "02:00"
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7

      backup_retention_settings {
        retained_backups = 7
      }
    }

    # Public IP with no authorized networks: only IAM-authorized Cloud SQL
    # connectors (the Cloud Run /cloudsql mount) can reach the instance.
    ip_configuration {
      ipv4_enabled = true
      ssl_mode     = "ENCRYPTED_ONLY"
    }

    maintenance_window {
      day  = 7
      hour = 2
    }
  }

  depends_on = [google_project_service.required["sqladmin.googleapis.com"]]

  lifecycle {
    # disk_autoresize grows the disk; don't let Terraform shrink it back.
    ignore_changes = [settings[0].disk_size]
  }
}

resource "google_sql_database" "app" {
  project  = var.project_id
  name     = var.db_name
  instance = google_sql_database_instance.db.name
}

# Ephemeral: the generated password is never written to plan or state. It is
# only sent through write-only arguments (the SQL user and DATABASE_URL secret).
ephemeral "random_password" "db" {
  length  = 32
  special = false
}

resource "google_sql_user" "app" {
  project             = var.project_id
  name                = var.db_user
  instance            = google_sql_database_instance.db.name
  password_wo         = ephemeral.random_password.db.result
  password_wo_version = var.db_password_version
}

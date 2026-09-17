variable "project_id" {
  description = "Google Cloud project that hosts the environment."
  type        = string
}

variable "region" {
  description = "Region for the VM, Cloud SQL, and the uploads bucket."
  type        = string
}

variable "environment" {
  description = "Environment name used in resource names (cuevolution-<environment>-*)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,15}$", var.environment))
    error_message = "environment must be 2-16 lowercase letters, digits or hyphens."
  }
}

variable "application_secrets_secret_id" {
  description = "Secret Manager secret holding the CUEVOLUTION_SECRETS_JSON blob (values added out of band)."
  type        = string
}

variable "profile_pictures_bucket" {
  description = "Globally unique name of the private bucket for player profile pictures."
  type        = string
}

variable "phx_host" {
  description = "Public host name of the web app; also the domain that gets mapped."
  type        = string
}

variable "mail_provider" {
  description = "App mail provider. smtp_relay is not supported: it needs a static egress IP."
  type        = string
  default     = "smtp_auth"

  validation {
    condition     = contains(["smtp_auth", "local"], var.mail_provider)
    error_message = "mail_provider must be smtp_auth or local."
  }
}

variable "sms_provider" {
  description = "App SMS provider."
  type        = string
  default     = "africastalking"

  validation {
    condition     = contains(["africastalking", "stub"], var.sms_provider)
    error_message = "sms_provider must be africastalking or stub."
  }
}

variable "mail_from_address" {
  description = "Sender address for outgoing mail."
  type        = string
}

variable "africastalking_sender_id" {
  description = "Africa's Talking sender ID."
  type        = string
  default     = "Cuevolution"
}

variable "db_tier" {
  description = "Cloud SQL machine tier. db-f1-micro is the smallest shared-core tier (no SLA); db-g1-small is the next step up."
  type        = string
  default     = "db-f1-micro"

  validation {
    condition     = can(regex("^db-", var.db_tier))
    error_message = "db_tier must be a Cloud SQL tier name such as db-f1-micro."
  }
}

variable "db_version" {
  description = "Cloud SQL PostgreSQL version."
  type        = string
  default     = "POSTGRES_18"

  validation {
    condition     = can(regex("^POSTGRES_[0-9]+$", var.db_version))
    error_message = "db_version must look like POSTGRES_18."
  }
}

variable "db_disk_size" {
  description = "Initial SSD size in GB (autoresize grows it)."
  type        = number
  default     = 10

  validation {
    condition     = var.db_disk_size >= 10
    error_message = "db_disk_size must be at least 10 GB."
  }
}

variable "db_name" {
  description = "Application database name. Must match the database being migrated in."
  type        = string
}

variable "db_user" {
  description = "Application database user. Must match the owner in the imported dump."
  type        = string
}

variable "db_password_version" {
  description = "Bump to rotate the generated database password (updates the SQL user and DATABASE_URL secret together)."
  type        = number
  default     = 1

  validation {
    condition     = var.db_password_version >= 1
    error_message = "db_password_version must be 1 or greater."
  }
}

variable "vm_machine_type" {
  description = "Machine type for the flat-rate web+worker VM (compute.tf), replacing the Cloud Run web/worker services."
  type        = string
  default     = "e2-small"
}

variable "vm_zone" {
  description = "Zone for the VM. Defaults to \"<region>-a\" when null."
  type        = string
  default     = null
}

variable "ssh_public_key" {
  description = "Public half of the deploy SSH keypair, added to the VM's metadata (GCE's ssh-keys mechanism) under the \"deploy\" username. Just the key material, e.g. the contents of deploy_key.pub minus any username prefix."
  type        = string
}

variable "ssh_allowed_cidrs" {
  description = "CIDR ranges allowed to SSH to the VM (port 22). GitHub Actions runners have no fixed IP range, so this defaults wide open; access is still gated by key-based auth only (no password auth)."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "project_id" {
  description = "Google Cloud project for production."
  type        = string
}

variable "region" {
  description = "Region for all regional resources."
  type        = string
  default     = "europe-west4"
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

variable "db_name" {
  description = "Database name; must match the database imported from the previous instance."
  type        = string
}

variable "db_user" {
  description = "Database user; must match the object owner in the imported dump."
  type        = string
}

variable "db_version" {
  description = "Cloud SQL PostgreSQL version (fall back to POSTGRES_17 if db-f1-micro rejects 18)."
  type        = string
  default     = "POSTGRES_18"
}

variable "ssh_public_key" {
  description = "Public half of the deploy SSH keypair (contents of deploy_key.pub, minus any username prefix — that's added automatically)."
  type        = string
}

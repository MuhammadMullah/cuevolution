variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "environment" {
  type = string
}

variable "image" {
  type        = string
  description = "Immutable Artifact Registry image reference, preferably pinned by digest."
}

variable "cloud_sql_connection_name" {
  type = string
}

variable "application_secrets_secret_id" {
  type = string
}

variable "storage_bucket" {
  type = string
}

variable "phx_host" {
  type = string
}

variable "mail_provider" {
  type    = string
  default = "local"
}

variable "sms_provider" {
  type    = string
  default = "stub"
}

variable "mail_from_address" {
  type    = string
  default = "notifications@cuevolution.test"
}

variable "africastalking_sender_id" {
  type    = string
  default = ""
}

variable "web_min_instances" {
  type    = number
  default = 0
}

variable "web_max_instances" {
  type    = number
  default = 3
}

variable "worker_min_instances" {
  type    = number
  default = 1
}

variable "worker_max_instances" {
  type    = number
  default = 1
}

variable "worker_ingress" {
  type    = string
  default = "INGRESS_TRAFFIC_INTERNAL_ONLY"
}

variable "secret_ids" {
  type = set(string)
}

variable "github_repository" {
  type        = string
  description = "GitHub repository in OWNER/REPOSITORY form allowed to deploy this environment."
}

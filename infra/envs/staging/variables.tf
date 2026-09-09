variable "project_id" {
  type    = string
  default = "cuevolution-staging"
}

variable "region" {
  type    = string
  default = "africa-south1"
}

variable "image" {
  type        = string
  description = "Artifact Registry image pinned by digest."
}

variable "cloud_sql_connection_name" {
  type = string
}

variable "storage_bucket" {
  type = string
}

variable "mail_provider" {
  type    = string
  default = "smtp_auth"
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
  default = "Cuevolution"
}

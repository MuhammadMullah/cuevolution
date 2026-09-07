variable "project_id" {
  type = string
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

variable "mail_from_address" {
  type = string
}

variable "africastalking_sender_id" {
  type    = string
  default = ""
}

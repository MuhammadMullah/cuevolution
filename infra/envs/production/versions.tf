terraform {
  required_version = ">= 1.11.0"

  backend "gcs" {}

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.7.1"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region

  # Local runs use user Application Default Credentials without a quota
  # project; bill API usage (e.g. the Organization Policy API) to this project.
  billing_project       = var.project_id
  user_project_override = true
}

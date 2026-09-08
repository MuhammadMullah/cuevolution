module "cuevolution" {
  source = "../../modules/cuevolution-runtime"

  project_id                 = var.project_id
  region                     = var.region
  environment                = "production"
  github_repository          = "MuhammadMullah/cuevolution"
  image                      = var.image
  cloud_sql_connection_name  = var.cloud_sql_connection_name
  application_secrets_secret_id = "cuevolution-production-application-secrets"
  storage_bucket             = var.storage_bucket
  phx_host                   = "sportpesapool.ke"
  mail_provider              = "smtp_relay"
  sms_provider               = "africastalking"
  mail_from_address          = var.mail_from_address
  africastalking_sender_id   = var.africastalking_sender_id
  web_min_instances          = 1
  web_max_instances          = 10
  worker_min_instances       = 1
  worker_max_instances       = 2

  secret_ids = toset([
    "cuevolution-production-application-secrets"
  ])
}

module "cuevolution" {
  source = "../../modules/cuevolution-runtime"

  project_id                 = var.project_id
  region                     = var.region
  environment                = "staging"
  github_repository          = "MuhammadMullah/cuevolution"
  image                      = var.image
  cloud_sql_connection_name  = var.cloud_sql_connection_name
  application_secrets_secret_id = "cuevolution-staging-application-secrets"
  storage_bucket             = var.storage_bucket
  phx_host                   = "staging.sportpesapool.ke"
  mail_provider              = var.mail_provider
  sms_provider               = var.sms_provider
  mail_from_address          = var.mail_from_address
  africastalking_sender_id   = var.africastalking_sender_id
  web_min_instances          = 0
  web_max_instances          = 3
  worker_min_instances       = 1
  worker_max_instances       = 1

  secret_ids = toset([
    "cuevolution-staging-application-secrets"
  ])
}

module "cuevolution" {
  source = "../../modules/cuevolution-runtime"

  project_id                    = var.project_id
  region                        = var.region
  environment                   = "production"
  application_secrets_secret_id = "cuevolution-production-application-secrets"
  profile_pictures_bucket       = "cuevolution-production-profile-pictures-ew4"
  phx_host                      = "sportpesapool.ke"
  mail_provider                 = "smtp_auth"
  sms_provider                  = "africastalking"
  mail_from_address             = var.mail_from_address
  africastalking_sender_id      = var.africastalking_sender_id
  db_tier                       = "db-f1-micro"
  db_version                    = var.db_version
  db_name                       = var.db_name
  db_user                       = var.db_user
  db_password_version           = 1
  ssh_public_key                = var.ssh_public_key
}
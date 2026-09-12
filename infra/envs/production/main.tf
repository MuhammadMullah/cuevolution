module "cuevolution" {
  source = "../../modules/cuevolution-runtime"

  project_id                    = var.project_id
  region                        = var.region
  environment                   = "production"
  github_repository             = "MuhammadMullah/cuevolution"
  image                         = var.image
  application_secrets_secret_id = "cuevolution-production-application-secrets"
  profile_pictures_bucket       = "cuevolution-production-profile-pictures-ew4"
  phx_host                      = "sportpesapool.ke"
  map_custom_domain             = var.map_custom_domain
  mail_provider                 = "smtp_auth"
  sms_provider                  = "africastalking"
  mail_from_address             = var.mail_from_address
  africastalking_sender_id      = var.africastalking_sender_id
  web_min_instances             = 1
  web_max_instances             = 3
  worker_min_instances          = 1
  worker_max_instances          = 2

  secret_ids = toset([
    "cuevolution-production-application-secrets"
  ])
}

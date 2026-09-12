# Cloud Run domain mapping (Preview) attaches the apex domain straight to the
# web service, with a Google-managed certificate and no load balancer. The
# identity running Terraform must be a verified owner of the domain in Google
# Search Console. Enable it only when DNS is ready to move: the certificate is
# provisioned after the apex A/AAAA records point at Google.
resource "google_cloud_run_domain_mapping" "apex" {
  count = var.map_custom_domain ? 1 : 0

  project  = var.project_id
  location = var.region
  name     = var.phx_host

  metadata {
    namespace = var.project_id
  }

  spec {
    route_name = google_cloud_run_v2_service.web_app.name
  }
}

# The cuevolutionke.com organization enforces constraints/sql.restrictPublicIp
# (enabled 2026-09-12). This project opts out so the Cloud SQL instance can keep
# a public IP. The instance has no authorized networks, so only IAM-authorized
# Cloud SQL connectors (the Cloud Run /cloudsql mount) can reach it. Remove this
# policy if the database moves to private IP.
resource "google_org_policy_policy" "allow_sql_public_ip" {
  name   = "projects/${var.project_id}/policies/sql.restrictPublicIp"
  parent = "projects/${var.project_id}"

  spec {
    rules {
      enforce = "FALSE"
    }
  }

  depends_on = [google_project_service.required["orgpolicy.googleapis.com"]]
}

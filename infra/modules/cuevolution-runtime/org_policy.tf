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

# The organization also enforces constraints/compute.vmExternalIpAccess (a
# list constraint, not a boolean like the one above) — no VM may have an
# external IP unless explicitly listed. This VM (compute.tf) needs one:
# Caddy publishes 80/443 directly, and a load balancer/Cloud NAT would be
# extra always-on cost for what's meant to be a single flat-rate box. Listing
# just this one instance, rather than disabling the constraint project-wide,
# keeps the exception as narrow as the SQL one above.
resource "google_org_policy_policy" "allow_vm_external_ip" {
  name   = "projects/${var.project_id}/policies/compute.vmExternalIpAccess"
  parent = "projects/${var.project_id}"

  spec {
    rules {
      values {
        allowed_values = [
          "projects/${var.project_id}/zones/${coalesce(var.vm_zone, "${var.region}-a")}/instances/cuevolution-${var.environment}-vm",
        ]
      }
    }
  }

  depends_on = [google_project_service.required["orgpolicy.googleapis.com"]]
}

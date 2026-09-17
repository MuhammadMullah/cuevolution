# Cuevolution Google Cloud infrastructure

One production environment in project `cuevolution-app`, region
`europe-west4`. There is no staging, no Cloud NAT, no static egress IP, no VPC
and no load balancer.

Compute (Phoenix web + Oban worker) runs on a single flat-rate GCE VM, not
Cloud Run — see `app/deploy/README.md` for the full deployment story (Docker
Compose stack, Caddy/TLS, CI/CD, rollback). This file covers the Terraform
side only.

| Component | Resource | Managed by |
|---|---|---|
| Compute | GCE VM `cuevolution-production-vm` (web + worker containers) | Terraform (`compute.tf`); deploys via `.github/workflows/deploy-vm.yml` |
| Database | Cloud SQL PostgreSQL `cuevolution-production-db`, `db-f1-micro`, public IP with no authorized networks, connector-only (project exception to the org's `sql.restrictPublicIp` policy, see `org_policy.tf`) | Terraform |
| Uploads | Private bucket `cuevolution-production-profile-pictures-ew4` | Terraform |
| Secrets | `cuevolution-production-application-secrets` (JSON, values added by hand) and `cuevolution-production-vm-database-url` (written by Terraform, never stored in state) | Terraform |

Code layout: `envs/production` is the only root; `modules/cuevolution-runtime`
holds the resources, split by concern (`apis.tf`, `compute.tf`, `org_policy.tf`,
`sql.tf`, `secrets.tf`, `storage.tf`).

## Running Terraform

Requires Terraform 1.11+ (write-only arguments).

```bash
cp infra/envs/production/production.tfvars.example infra/envs/production/production.tfvars
# fill in db_name, db_user, mail_from_address, ssh_public_key

terraform -chdir=infra/envs/production init \
  -backend-config="bucket=cuevolution-production-tf-state" \
  -backend-config="prefix=cuevolution/production"
terraform -chdir=infra/envs/production plan -var-file=production.tfvars
```

Connection budget for `db-f1-micro` (about 25 connections): the VM is the
only thing connecting, so `POOL_SIZE` (app) + `POOL_SIZE` (worker) must stay
comfortably under that — see the `POOL_SIZE` note in `app/deploy/README.md`.
To grow, set `db_tier = "db-g1-small"` (about 50 connections).

One thing worth knowing if you ever need to remove a `deletion_protection`-guarded
resource (the VM has it, `google_compute_instance.app`): it's a
Terraform-provider-side guard, not a real GCP property, and it hard-fails a
destroy unless flipped to `false` first *while the resource still exists in
config* — do that as its own preliminary `apply` before deleting the
resource from config, not in the same step (see "Decommissioning Cloud Run"
in `app/deploy/README.md` for exactly how this played out removing Cloud Run).

## Secrets

`cuevolution-production-application-secrets` holds one JSON version with the
values below; Terraform never writes it. Add a version outside the repository:

```bash
gcloud secrets versions add cuevolution-production-application-secrets \
  --project=cuevolution-app --data-file=production-secrets.json
```

```json
{
  "SECRET_KEY_BASE": "...",
  "SMTP_USERNAME": "admin@cuevolutionke.com",
  "SMTP_PASSWORD": "<Google app password>",
  "AFRICASTALKING_API_KEY": "...",
  "AFRICASTALKING_USERNAME": "..."
}
```

`DATABASE_URL` comes from `cuevolution-production-vm-database-url`, generated
with the database password (same password as the SQL user, just a
TCP-through-cloud-sql-proxy-shaped URL instead of a Unix socket one). A plain
env var overrides the same key in the JSON blob. To rotate the database
password, bump `db_password_version` and apply, then redeploy so the VM
fetches the new secret version.

Mail must use `smtp_auth`: there is no static egress IP, so the IP-allowlisted
`smtp_relay` mode cannot work.

## Deploys

Pushing to `main` runs `.github/workflows/deploy-vm.yml`: build and push the
image to GHCR, SSH to the VM, migrate, restart the `app`/`worker` containers.
See `app/deploy/README.md` for the full setup (one-time server config,
GitHub secrets, rollback, the zero-downtime DNS cutover this replaced Cloud
Run with).

## Migration from Cloud Run to a VM (completed 2026-09-16)

Full runbook and rationale live in `app/deploy/README.md` (kept there since
it's mostly about the VM/Docker Compose side, not Terraform). Short version:
Cloud Run's per-request billing and scale-to-zero didn't fit a flat-rate
budget, so compute moved to one GCE VM running the same release image as
both `app` (web) and `worker` containers, behind Caddy with a Cloudflare
DNS-01 challenge that let it hold a valid cert before DNS ever pointed at
it — the DNS cutover between Cloud Run and the VM was zero-downtime because
of that. Cloud Run was verified working in parallel for a while, then its
46 resources (`run.tf`, `domain.tf`, the Cloud Build/Workload-Identity-Federation
resources that were in `iam.tf`) were destroyed as a separate, deliberate
Terraform change — never bundled with provisioning the VM, so no `plan`/`apply`
along the way risked touching the still-live service. Cloud SQL and the GCS
bucket were untouched throughout; only the compute layer moved.

## Migration from africa-south1 (completed 2026-09-13)

Kept for reference. The old stack and the `cuevolution-staging` project have
been torn down; only the old subnet and network `cuevolution-production-runtime`
remain until Cloud Run releases its reserved serverless IP (1-2 hours after the
services were deleted), after which they can be deleted with gcloud.

Stop at any failed check. Every deletion in step 8 is confirmed before running.

0. **Prepare**
   - Verify `sportpesapool.ke` in Google Search Console with the identity that
     runs Terraform.
   - In Cloudflare, lower the apex record TTL a day ahead and turn off
     "Always Use HTTPS".
   - Confirm IP whitelisting is off in the Africa's Talking dashboard.
   - Find the old database name and user:
     `gcloud sql databases list --instance=cuevolution-prod --project=cuevolution-app`
     and `gcloud sql users list --instance=cuevolution-prod --project=cuevolution-app`.
1. **App first.** Merge the app changes (env-first secrets, `/health`
   excluded from `force_ssl`, Oban role switch) and let the existing pipeline
   deploy them to africa-south1. Note the deployed image digest; it becomes
   `image` in `production.tfvars`.
2. **Apply Terraform** from this branch (do not merge yet: merging deploys to
   europe-west4 and would run migrations on the empty database). Expect:
   creates for the database, user, secrets, bucket, registry, web service,
   migration job; old africa-south1 resources only "removed from state"; no
   destroys. If `POSTGRES_18` is rejected for `db-f1-micro`, set
   `db_version = "POSTGRES_17"` and apply again. If the database still fails
   with `constraints/sql.restrictPublicIp` right after the project exception
   is created, the policy is still propagating: wait a few minutes and apply
   again.
3. **Freeze the old stack** (maintenance starts):
   ```bash
   gcloud run services update cuevolution-production-web --region=africa-south1 --ingress=internal
   gcloud run services update cuevolution-production-worker --region=africa-south1 --update-env-vars=OBAN_ENABLED=false
   ```
4. **Copy data**
   ```bash
   gcloud storage buckets create gs://cuevolution-app-migration --location=europe-west4
   # grant the old and new instances' service agents access to the bucket
   gcloud sql export sql cuevolution-prod gs://cuevolution-app-migration/prod.sql.gz --database=DB_NAME
   gcloud sql import sql cuevolution-production-db gs://cuevolution-app-migration/prod.sql.gz --database=DB_NAME --user=DB_USER
   gcloud storage rsync -r gs://cuevolution-production-profile-pictures gs://cuevolution-production-profile-pictures-ew4
   ```
5. **Deploy** by merging the branch (or running the workflow). Check on the
   `web_url` output: sign-in, pages, profile pictures, a password-reset email,
   an SMS, and `gcloud beta run instances describe cuevolution-production-worker --region=europe-west4`
   shows the instance running.
6. **DNS cutover.** Set `map_custom_domain = true` and apply. Replace the
   Cloudflare apex record (currently `136.69.5.10`) with the
   `domain_dns_records` output, DNS-only. The certificate usually takes about
   15 minutes and can take up to 24 hours. Then set the `SMOKE_URL` variable
   and check `https://sportpesapool.ke/health/readiness` and a LiveView page.
   Rollback: point DNS back to `136.69.5.10` and undo step 3.
7. **Watch for 48-72 hours**: Cloud SQL connections below 20, error logs,
   worker restarts, billing.
8. **Tear down** (confirm each):
   - africa-south1 Cloud Run web/worker services and migrate job
   - load balancer: forwarding rule `cuevolution-production-web-https`, target
     HTTPS proxy, URL map `cuevolution-production-web-map`, backend service
     `cuevolution-production-web-backend`, NEG `cuevolution-production-web-neg`,
     certificate `cuevolution-production-web-cert`, address `cuevolution-production-web-ip`
   - Cloud NAT, router, subnet and network `cuevolution-production-runtime`,
     address `cuevolution-production-smtp-relay`
   - Cloud SQL `cuevolution-prod` (keep the final export)
   - africa-south1 Artifact Registry repository, buckets
     `cuevolution-production-profile-pictures` and `cuevolution-app-cloudbuild-source`
   - project `cuevolution-staging`; GitHub environment `staging`
   - `removed.tf` and `compute.googleapis.com` were then removed from the
     module (Terraform only forgets the API; `disable_on_destroy = false`)

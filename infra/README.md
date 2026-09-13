# Cuevolution Google Cloud infrastructure

One production environment in project `cuevolution-app`, region
`europe-west4`. There is no staging, no Cloud NAT, no static egress IP, no VPC
and no load balancer.

| Component | Resource | Managed by |
|---|---|---|
| Web | Cloud Run service `cuevolution-production-web` (scales to zero, request-based billing) | Terraform; image by Cloud Build |
| Domain | Cloud Run domain mapping `sportpesapool.ke` → web (Preview) | Terraform (`map_custom_domain`) |
| Background jobs | Cloud Run **instance** `cuevolution-production-worker` running Oban queues (Preview, always on) | Cloud Build (`cloudbuild.yaml`); Terraform owns its service account and IAM |
| Migrations | Cloud Run job `cuevolution-production-migrate` | Terraform; image by Cloud Build |
| Database | Cloud SQL PostgreSQL `cuevolution-production-db`, `db-f1-micro`, public IP with no authorized networks, connector-only (project exception to the org's `sql.restrictPublicIp` policy, see `org_policy.tf`) | Terraform |
| Images | Artifact Registry `cuevolution-images` (keeps 10 newest, deletes > 30 days) | Terraform |
| Uploads | Private bucket `cuevolution-production-profile-pictures-ew4` | Terraform |
| Secrets | `cuevolution-production-application-secrets` (JSON, values added by hand) and `cuevolution-production-database-url` (written by Terraform, never stored in state) | Terraform |

Code layout: `envs/production` is the only root; `modules/cuevolution-runtime`
holds the resources, split by concern (`apis.tf`, `iam.tf`, `sql.tf`,
`secrets.tf`, `storage.tf`, `run.tf`, `domain.tf`). `removed.tf` drops the old
africa-south1 runtime from state without destroying it; delete that file once
the teardown below is finished.

## Running Terraform

Requires Terraform 1.11+ (write-only arguments) and an identity that is a
verified owner of `sportpesapool.ke` in Google Search Console (for the domain
mapping).

```bash
cp infra/envs/production/production.tfvars.example infra/envs/production/production.tfvars
# fill in image digest, db_name, db_user, mail_from_address

terraform -chdir=infra/envs/production init \
  -backend-config="bucket=cuevolution-production-tf-state" \
  -backend-config="prefix=cuevolution/production"
terraform -chdir=infra/envs/production plan -var-file=production.tfvars
```

Connection budget for `db-f1-micro` (about 25 connections): web
`web_max_instances` x (`web_pool_size` + 1) + worker (`_WORKER_POOL_SIZE` + 1) +
migrate job (2) must stay at or below about 22. Defaults: 3 x 4 + 7 + 2 = 21.
To grow, set `db_tier = "db-g1-small"` (about 50 connections).

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

`DATABASE_URL` comes from `cuevolution-production-database-url`, generated
with the database password. A plain env var overrides the same key in the JSON
blob. To rotate the database password, bump `db_password_version` and apply,
then redeploy so new instances read the new secret version.

Mail must use `smtp_auth`: there is no static egress IP, so the IP-allowlisted
`smtp_relay` mode cannot work.

## Deploys

Pushing to `main` runs `.github/workflows/deploy-production.yml`, which submits
`cloudbuild.yaml`: build and push the image, run the migration job, update the
web service, then create or update the worker instance with the same plain env
vars as web (plus its own pool size and signing identity). The workflow
authenticates through Workload Identity Federation and only jobs running in the
protected `production` GitHub environment are accepted.

GitHub configuration: environment `production` with secrets
`GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_DEPLOYER_SERVICE_ACCOUNT` and
`GCP_PRODUCTION_PROJECT_ID`, plus the repository variable `SMOKE_URL` (empty
until DNS cutover, then `https://sportpesapool.ke`).

## Migration from africa-south1 (one-time runbook)

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
   - then delete `removed.tf` and `compute.googleapis.com` from `apis.tf`

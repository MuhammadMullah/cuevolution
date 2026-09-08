# Cuevolution Google Cloud infrastructure

This directory contains the Terraform configuration for the isolated staging
and production Cloud Run environments. It manages service accounts, IAM,
Artifact Registry, Secret Manager metadata/access, private Google Cloud
Storage buckets, and the Cloud Run web and Oban worker services.

The configuration deliberately does not contain secret values. Add secret
versions in Secret Manager separately, then apply Terraform with the matching
project and Cloud SQL connection name.

## Adopt the manually-created staging resources

The staging project, repository, Cloud Run service, and load balancer were
created manually while validating the migration. Before the first staging
`terraform apply`, import any resources that already exist into the matching
state. Do not apply an empty state against those names without importing them.

The load balancer remains a separate adoption step because its certificate and
DNS provisioning are asynchronous. The resource list is documented in the
environment README and can be added to state after the HTTPS endpoint is
stable.

## Local validation

Create one private Google Cloud Storage bucket per environment for locked
Terraform state, then initialize each root with its bucket and prefix:

```bash
terraform -chdir=infra/envs/staging init \
  -backend-config="bucket=REPLACE_WITH_STAGING_TF_STATE_BUCKET" \
  -backend-config="prefix=cuevolution/staging"
terraform -chdir=infra/envs/production init \
  -backend-config="bucket=REPLACE_WITH_PRODUCTION_TF_STATE_BUCKET" \
  -backend-config="prefix=cuevolution/production"
```

```bash
terraform -chdir=infra/envs/staging fmt -check
terraform -chdir=infra/envs/staging validate
terraform -chdir=infra/envs/staging plan -var-file=staging.tfvars
```

Use a remote, locked state backend before applying from CI. The example roots
use the Google provider and are intentionally explicit about project IDs and
regions so a staging run cannot silently target production.

## GitHub Actions setup

Create a GitHub Actions environment named `staging` and add these secrets:

- `GCP_WORKLOAD_IDENTITY_PROVIDER`: Terraform output
  `github_workload_identity_provider`
- `GCP_DEPLOYER_SERVICE_ACCOUNT`: Terraform output
  `github_deployer_service_account`

Create a protected `production` environment with the same two secret names and
require an approval before the production workflow can run. The production
workflow also needs `GCP_PRODUCTION_PROJECT_ID`.

The workflows submit the source to Google Cloud Build. Cloud Build builds and
pushes a commit-tagged image to Artifact Registry, resolves its digest, runs
the environment's migration job, then deploys the web and worker services by
digest. No Docker daemon or long-lived Google service-account key is used on
the GitHub runner. Terraform creates a dedicated `cuevolution-<environment>-cb`
service account and the workflow explicitly selects it for each build.

## Secret versions

Terraform creates one secret per environment and grants access to the web,
worker, and migration identities, but never writes its value. Add a JSON
version before deploying a Cloud Run revision:

```json
{
  "DATABASE_URL": "ecto://...",
  "SECRET_KEY_BASE": "...",
  "AFRICASTALKING_API_KEY": "...",
  "AFRICASTALKING_USERNAME": "..."
}
```

Only include provider-specific keys that the environment uses. Save this file
outside the repository and upload it with:

```bash
gcloud secrets versions add cuevolution-staging-application-secrets \
  --project=cuevolution-staging --data-file=staging-secrets.json
```

The application reads `CUEVOLUTION_SECRETS_JSON` once at boot. It still accepts
individual environment variables as a local-development fallback, but the
Terraform-managed Cloud Run services use the single JSON secret.

The `smtp_relay_static_ip` Terraform output is the public Cloud NAT address to
allow in Google Workspace SMTP relay settings for the corresponding environment.

## Importing existing staging resources

Import existing resources before applying the staging root. Typical imports
include:

```bash
terraform -chdir=infra/envs/staging import \
  'module.cuevolution.google_artifact_registry_repository.images' \
  projects/cuevolution-staging/locations/africa-south1/repositories/cuevolution-images

terraform -chdir=infra/envs/staging import \
  'module.cuevolution.google_cloud_run_v2_service.web' \
  projects/cuevolution-staging/locations/africa-south1/services/cuevolution-staging-web

terraform -chdir=infra/envs/staging import \
  'module.cuevolution.google_cloud_run_v2_job.migrate' \
  projects/cuevolution-staging/locations/africa-south1/jobs/cuevolution-staging-migrate
```

Import the manually-created worker only if it already exists. The load
balancer, certificate, static IP, and serverless NEG should also be imported
before adding their Terraform resources; until then, keep those resources
managed manually as documented in the migration plan.

## GCS migration

The profile-picture bucket is private. Cloud Run service accounts receive
`roles/storage.objectUser` and self-signing permission for V4 URLs through IAM
Credentials; no AWS credentials or Google service-account key files are used.
If the old S3 bucket contains existing objects, copy them into the new bucket
before switching production traffic, preserving the `players/...` object keys.

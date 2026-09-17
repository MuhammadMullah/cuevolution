# Production deployment: GCE VM + Docker Compose + Caddy

This replaces Cloud Run for production compute — see `infra/README.md` for
the still-active Terraform-managed pieces: Cloud SQL and the GCS uploads
bucket, both unchanged by this move. The VM itself — service account,
static IP, firewall rules — is provisioned
by Terraform (`infra/modules/cuevolution-runtime/compute.tf`); everything
below is what happens on top of that VM, one time, plus what the CI/CD
workflow does on every push.

Single server, one environment (production). Two containers from the same
release image (Phoenix web + Oban worker), a Cloud SQL Auth Proxy sidecar,
and a Caddy reverse proxy — see `app/deploy/app/docker-compose.yml`.

Every pull request runs `.github/workflows/ci.yml` — format check,
`mix compile --warnings-as-errors`, `mix credo --strict`, `mix test`. The
deploy workflow (`.github/workflows/deploy-vm.yml`) runs the same checks
(via the shared `.github/workflows/test.yml`) before building or deploying
anything.

On push, the deploy workflow builds the Docker image from `app/Dockerfile`,
pushes it to GHCR, SSHes into the VM, pulls the new image, runs migrations,
and restarts the `app`/`worker` containers. It never touches the Caddy
stack (`app/deploy/caddy/`) — that's provisioned once during setup, not
per-deploy.

Note: `.github/workflows/` lives at the repo root, one level up from this
`app/` directory, even though everything else deploy-related is in here —
GitHub only ever looks for workflows at the repository root.

## Why the DB and storage env vars look the way they do

- `cloud-sql-proxy` needs no mounted key file: it authenticates as the VM's
  attached service account automatically via the instance metadata server —
  the same mechanism `lib/cuevolution/accounts/profile_picture/storage/gcs/requester/live.ex`
  already uses for GCS, so that file needs no changes for this move.
- `DATABASE_URL` points at `cloud-sql-proxy:5432` (a plain TCP Ecto URL) with
  `DB_SSL=false` — the proxy itself encrypts the hop to Cloud SQL; the
  app→proxy hop stays inside the VM's private Docker network.
- `GCS_SIGNING_SERVICE_ACCOUNT` must be the VM's service account email
  (`terraform output vm_service_account`) — it needs
  `roles/iam.serviceAccountTokenCreator` on itself to sign V4 URLs, which
  `compute.tf` already grants.
- `POOL_SIZE` defaults to `10`: `db-f1-micro` allows only ~25 total
  connections, and this VM is the only thing connecting now that Cloud Run
  is decommissioned. While Cloud Run was still live in parallel during the
  migration, a higher value here caused real `too_many_connections`
  failures — drop it back to ~3 if Cloud Run is ever temporarily
  resurrected for a rollback.
- `DATABASE_URL` and `CUEVOLUTION_SECRETS_JSON` (`SECRET_KEY_BASE`,
  `SMTP_USERNAME`/`PASSWORD`, `AFRICASTALKING_API_KEY`/`USERNAME`) are never
  written to `.env` on disk. `deploy.sh` fetches them fresh from Secret
  Manager on every deploy — the exact same secrets Cloud Run's
  `--set-secrets` already reads (`secrets.tf`'s `application` and
  `vm_database_url` secrets), just pulled via `gcloud` using the VM's
  attached service account instead of a Cloud Run mount.

## One-time server setup

All of this happens once, on the VM Terraform created.

1. **Provision the VM.** From `infra/envs/production`:

   ```
   terraform apply
   ```

   This creates the VM, its service account, a static external IP, and
   firewall rules for 80/443/22 — Cloud Run keeps serving traffic
   unaffected; nothing existing is touched. Docker Engine, the compose
   plugin, and the `gcloud` CLI install automatically on first boot via the
   instance's startup script (`gcloud` needs no login on the VM — it picks
   up the attached service account from the metadata server automatically).
   Note the outputs `vm_ip`, `vm_service_account`, `db_connection_name`,
   `vm_database_url_secret_id`.

2. **Add your SSH key.** GCE VMs take SSH keys via instance/project
   metadata rather than a manually managed `authorized_keys` file:

   ```
   ssh-keygen -t ed25519 -f deploy_key -N ""
   gcloud compute instances add-metadata cuevolution-production-vm \
     --project=<project_id> --zone=<zone> \
     --metadata=ssh-keys="deploy=$(cat deploy_key.pub)"
   ```

   `deploy_key` (the private half) becomes the `SSH_PRIVATE_KEY` secret
   below — never commit it.

3. **Create the shared Docker network** the reverse proxy and the app stack
   both join:

   ```
   ssh deploy@<vm_ip> docker network create web
   ```

4. **Deploy the Caddy stack** (once). DNS does **not** need to point here
   yet — the Caddyfile uses a DNS-01 challenge via the Cloudflare API
   (`caddy-dns/cloudflare`, built by `deploy/caddy/Dockerfile`), so it can
   fetch a real cert for `sportpesapool.ke` while Cloud Run is still the
   one actually serving that domain. This is what makes the eventual
   cutover zero-downtime — see "Zero-downtime DNS cutover" below.

   ```
   ssh deploy@<vm_ip> 'sudo mkdir -p /opt/caddy && sudo chown $(whoami) /opt/caddy'
   scp app/deploy/caddy/docker-compose.yml app/deploy/caddy/Caddyfile \
       app/deploy/caddy/Dockerfile app/deploy/caddy/.env.example \
     deploy@<vm_ip>:/opt/caddy/
   ssh deploy@<vm_ip>
   cd /opt/caddy && mv .env.example .env   # fill in CADDY_EMAIL and CF_API_TOKEN
   docker compose --env-file .env up -d --build
   docker compose logs caddy   # confirm it obtained the certificate, no errors
   ```

5. **Mail credentials.** Production uses `MAIL_PROVIDER=smtp_auth`
   (`config/runtime.exs`), which relays through `smtp.gmail.com:587` with a
   Gmail account/app-password. Nothing to do here — `SMTP_USERNAME`/
   `SMTP_PASSWORD` already live inside the `application` Secret Manager
   secret Cloud Run reads from, and `deploy.sh` (step 7) fetches that same
   secret. No new credentials, no copy-paste.

6. **Create the app directory and copy the compose file + deploy script:**

   ```
   ssh deploy@<vm_ip> 'sudo mkdir -p /opt/cuevolution-production && sudo chown $(whoami) /opt/cuevolution-production'
   scp app/deploy/app/docker-compose.yml app/deploy/app/.env.example app/deploy/app/deploy.sh \
     deploy@<vm_ip>:/opt/cuevolution-production/
   ssh deploy@<vm_ip>
   cd /opt/cuevolution-production && mv .env.example .env && chmod +x deploy.sh
   ```

   Fill in `.env` — see the comments in `app/deploy/app/.env.example` for
   where each value comes from (`terraform output`, or `production.tfvars`
   for the bucket name). Notice what's *not* there: `DATABASE_URL` and the
   app secrets aren't in this file at all — `deploy.sh` fetches them fresh
   from Secret Manager every run. This file is **never** touched by CI
   except its `IMAGE=` line, and never leaves the server.

7. **First deploy:**

   ```
   cd /opt/cuevolution-production
   ./deploy.sh ghcr.io/muhammadmullah/cuevolution:production
   ```

   This sets `IMAGE=` in `.env`, exports `DATABASE_URL`/
   `CUEVOLUTION_SECRETS_JSON` from Secret Manager for just this run, pulls,
   migrates, restarts `app`/`worker`, and smoke-tests `/health/readiness`.
   After this, pushes to `main` handle everything automatically.

   The app is now fully live on the VM, behind a Caddy that already holds a
   valid cert for the real domain — just not receiving any public traffic
   yet, since DNS still points at Cloud Run. Verify it end-to-end without
   touching DNS by adding a temporary line to your own machine's
   `/etc/hosts` (`<vm_ip> sportpesapool.ke`), then browsing
   `https://sportpesapool.ke` as if you were a real visitor: login, a
   profile picture upload (exercises GCS), an Oban-backed action (exercises
   the `worker` container). Remove the `/etc/hosts` line when done.

8. **Make the GHCR package pullable from the VM.** Images push to
   `ghcr.io/<owner>/cuevolution` as *private* by default. Either:
   - Make the package public (Package settings on GitHub → Change
     visibility) — simplest, fine if the source isn't sensitive, or
   - `docker login ghcr.io` on the VM with a
     [PAT](https://github.com/settings/tokens) that has `read:packages`
     scope.

## GitHub configuration

Create a `production` [GitHub Environment](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment)
(Settings → Environments) with:

| Secret            | Value                                            |
| ------------------ | ------------------------------------------------- |
| `SSH_HOST`         | The VM's static IP (`terraform output vm_ip`)    |
| `SSH_USER`         | The deploy user from step 2 above                |
| `SSH_PRIVATE_KEY`  | Contents of `deploy_key` (the private key, not `.pub`) |
| `SSH_PORT`         | Usually `22`                                     |

No GHCR secret is needed — the workflow pushes using the automatically
provided `GITHUB_TOKEN` (with `packages: write` permission set in the
workflow itself).

Optionally, add branch protection on `main` requiring the `CI` workflow to
pass before merging — this repo's workflow files alone can't turn that on;
it's a Settings → Branches rule.

## Zero-downtime DNS cutover

By this point Cloud Run is still serving `sportpesapool.ke` and the VM is
fully working and already holds a valid cert for that same domain (step 4's
DNS-01 challenge doesn't require DNS to point here). That's what makes the
cutover itself safe:

1. Confirm `deploy-vm.yml` has been run at least once via
   `workflow_dispatch` and deployed successfully (see "GitHub
   configuration" above).
2. At Cloudflare, lower `sportpesapool.ke`'s A record TTL (e.g. to 60s) a
   few minutes ahead, so the change below propagates fast — this speeds up
   the transition but isn't required for correctness, since both ends serve
   the same app/data throughout.
3. Change the A record to the VM's static IP (`terraform output vm_ip`).
   Leave Cloud Run running — don't remove its Terraform resources yet.
   Every client is now correctly served regardless of whether their
   resolver has the old or new record cached: Cloud Run still works until
   decommissioned, and the VM already works and already has its cert.
4. Watch both: the VM's `docker compose logs -f app worker caddy` and Cloud
   Run's logs/metrics in the GCP console. Once traffic has visibly shifted
   and stayed healthy on the VM for a while (comfortably past the old TTL),
   move on.
5. Flip `deploy-vm.yml`'s trigger to `push: branches: [main]` and delete or
   disable `.github/workflows/deploy-production.yml` — the VM is now the
   real deploy target.
6. Only afterwards, as a separate change (see "Decommissioning Cloud Run"
   below), remove the Cloud Run resources.

## Rolling back

Each deploy is tagged with its commit SHA (`production-<sha>`), not just the
floating `production` tag. To roll back, SSH in and re-run `deploy.sh` with
an older tag:

```
cd /opt/cuevolution-production
./deploy.sh ghcr.io/muhammadmullah/cuevolution:production-<old-sha>
```

(Skip re-running migrations on rollback unless you're also reverting the
schema — `bin/migrate` is idempotent but a *down* migration needs
`bin/cuevolution eval "Cuevolution.Release.rollback(Cuevolution.Repo, <version>)"`
run manually.)

## Decommissioning Cloud Run

Done on 2026-09-16, once the VM had served production successfully for a
while: removed the Cloud Run resources (`run.tf`, `domain.tf`, the Cloud
Build/Workload-Identity-Federation resources that were in `iam.tf`),
`cloudbuild.yaml`, and `.github/workflows/deploy-production.yml` — 46
resources destroyed via Terraform, deliberately as its own separate change
after DNS cutover and verification, not bundled with standing the VM up.
Cloud SQL, the GCS bucket, and everything the VM uses were untouched.

One thing worth knowing if you're reading this later: `google_compute_instance.app`
has `deletion_protection = true`, and the two removed Cloud Run resources
had it too — that's a Terraform-provider-side guard that hard-fails a
destroy unless flipped to `false` first *while the resource still exists in
config*. If you ever need to remove another `deletion_protection`-guarded
resource, do that flip as its own preliminary `apply` before deleting the
resource from config, not in the same step.

There's now no quick rollback path to Cloud Run — that infrastructure is
gone. A serious regression means rolling back the VM's own deploy (see
"Rolling back" above) or rebuilding Cloud Run from scratch via Terraform.

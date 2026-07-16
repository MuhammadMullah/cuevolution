# Deployment

One Debian server hosting both environments, one shared reverse proxy in
front of two independent app+database stacks:

| Branch    | Workflow                                   | Environment  | Domain                       |
| --------- | ------------------------------------------- | ------------ | ------------------------------ |
| `develop` | `.github/workflows/deploy-staging.yml`      | `staging`    | `staging.cuevolutionke.com`  |
| `main`    | `.github/workflows/deploy-production.yml`   | `production` | `cuevolutionke.com`          |

Every pull request (regardless of target branch) also runs `.github/workflows/ci.yml`
— format check, `mix compile --warnings-as-errors`, `mix credo --strict`,
`mix test`. Both deploy workflows run the same checks (via the shared
`.github/workflows/test.yml`) before building or deploying anything, so a
broken `develop`/`main` push never reaches the server even if branch
protection isn't configured.

On push, the deploy workflow builds the Docker image from `app/Dockerfile`,
pushes it to GHCR, copies `app/deploy/app/docker-compose.yml` to that
environment's own directory on the server, then SSHes in to pull the new
image, run migrations, and restart just that stack. It never touches the
shared Caddy stack (`app/deploy/caddy/`) — that's server-level infra,
deployed once during setup, not per-deploy.

Note: `.github/workflows/` lives at the repo root, one level up from this
`app/` directory, even though everything else deploy-related is in here —
GitHub only ever looks for workflows at the repository root.

## Why one shared Caddy instead of one per environment

Two Caddy containers can't both bind ports 80/443 on the same host. So the
topology is: one Caddy stack (`deploy/caddy/`) doing TLS termination and
routing by domain, and two independent app+db stacks (`deploy/app/`,
deployed twice under different directories/`.env`s) that Caddy reverse-proxies
to by container name over a shared Docker network called `web`. The two
app stacks never talk to each other or share a database — only Caddy
bridges them.

## One-time server setup

All of this happens once, on the single server, in this order (Caddy needs
the app containers' network to exist, and needs DNS pointed at it before
it can request certificates).

1. **Install Docker.** Follow [Docker's install guide](https://docs.docker.com/engine/install/)
   for Debian; the `docker compose` plugin (v2, not the standalone
   `docker-compose` binary) needs to be present — check with
   `docker compose version`.

2. **Create a deploy user** (or reuse an existing one) that's in the
   `docker` group, and generate an SSH keypair for GitHub Actions to use:

   ```
   ssh-keygen -t ed25519 -f deploy_key -N ""
   ```

   Add `deploy_key.pub` to that user's `~/.ssh/authorized_keys` on the
   server. `deploy_key` (the private half) becomes the `SSH_PRIVATE_KEY`
   secret below — never commit it. The same key/user is used for both
   environments, since it's the same server.

3. **Create the shared Docker network** the reverse proxy and both app
   stacks all join:

   ```
   docker network create web
   ```

4. **Point DNS** for both `staging.cuevolutionke.com` and the bare
   `cuevolutionke.com` at the server's IP — required before Caddy can
   obtain Let's Encrypt certificates for either. For the apex domain
   specifically, make sure it has **only** that one A record — a
   registrar's default parking/forwarding records left in place alongside
   it will make certificate issuance (and traffic) unreliable, since
   requests can land on any of the listed IPs.

5. **Deploy the shared Caddy stack** (once — not part of either app's CI/CD):

   ```
   sudo mkdir -p /opt/caddy && sudo chown $(whoami) /opt/caddy
   ```

   Copy `app/deploy/caddy/docker-compose.yml`, `app/deploy/caddy/Caddyfile`,
   and `app/deploy/caddy/.env.example` (as `.env`, filled in) from this
   repo to `/opt/caddy` on the server, then:

   ```
   cd /opt/caddy
   docker compose --env-file .env up -d
   ```

6. **For each environment** (staging, then production):

   - Create an AWS S3 bucket for it (a **separate** bucket per
     environment — don't share one), with default settings (**Block all
     public access** left ON — the bucket stays private; the app serves
     photos through short-lived presigned URLs rather than a public
     endpoint, see `lib/cuevolution/accounts/profile_picture/storage/s3.ex`).

     Create an IAM user (or role, if the server itself runs on AWS) with
     an inline policy scoped to just that bucket (email no longer goes
     through AWS — see Postmark setup below):

     ```json
     {
       "Version": "2012-10-17",
       "Statement": [
         {
           "Effect": "Allow",
           "Action": ["s3:PutObject", "s3:GetObject"],
           "Resource": "arn:aws:s3:::<bucket-name>/*"
         }
       ]
     }
     ```

     Generate an access key for that IAM user (Security credentials →
     Access keys) and note the bucket's region — both go in `.env` below.

   - **Set up Postmark** (sends over Postmark's SMTP relay):
     - Create a server in the Postmark account (Servers → create one per
       environment, e.g. "staging" / "production", so bounces/activity
       don't mix) and copy its **Server API Token** (Servers → your
       server → API Tokens) — this becomes both `POSTMARK_SMTP_USERNAME`
       and `POSTMARK_SMTP_PASSWORD` below. `POSTMARK_SMTP_HOST` is
       `smtp.postmarkapp.com`; use port `2525` for `POSTMARK_SMTP_PORT`,
       not the standard `587` — this server's outbound 587 is blocked at
       the network level (confirmed by connecting directly from inside
       the app container: `docker compose exec app bin/cuevolution rpc
       "IO.inspect(:gen_tcp.connect(~c\"smtp.postmarkapp.com\", 587, [],
       5000))"` returned `{:error, :timeout}`, while port `2525` — an
       alternate Postmark offers for exactly this situation — connected
       fine). If you ever see stuck `status: "sending"` rows in the
       `notifications` table with no `error` recorded, re-run that same
       check against whichever port is configured.
     - Verify a Sender Signature: either a single email address (Sender
       Signatures → Add, then click the confirmation link it emails you),
       or an entire domain via DKIM/Return-Path DNS records (Sender
       Signatures → Domains — lets you send from any address
       `@your-domain` without re-verifying each one). This becomes
       `MAIL_FROM_ADDRESS` below.
     - New Postmark accounts start in **trial mode** with a sending cap
       and Postmark's own review before full sending is unlocked —
       request approval under your account's settings once you're ready
       for real traffic.

   - Create the app directory:

     ```
     sudo mkdir -p /opt/cuevolution-staging   # or -production
     sudo chown $(whoami) /opt/cuevolution-staging
     ```

   - Copy `app/deploy/app/.env.example` from this repo to
     `/opt/cuevolution-staging/.env` (or `-production`) and fill in real
     values — `APP_CONTAINER_NAME` and `DOMAIN` especially need to match
     what's in `app/deploy/caddy/Caddyfile` exactly, or Caddy won't be
     able to reach this app. `SECRET_KEY_BASE`: generate with
     `mix phx.gen.secret`. This file is **never** touched by CI except for
     its `IMAGE=` line, and never leaves the server.

   - **First deploy is manual**, since `docker-compose.yml`/`.env` don't
     exist until the step above, and the app needs *a* image reference
     before the workflow's `sed` can update it:

     ```
     cd /opt/cuevolution-staging   # or -production
     echo "IMAGE=ghcr.io/<owner>/cuevolution:staging" >> .env   # or :production
     docker compose --env-file .env pull
     docker compose --env-file .env run --rm app bin/migrate
     docker compose --env-file .env up -d
     ```

     After this, pushes to `develop`/`main` handle everything automatically.

7. **Make the GHCR package pullable from the server.** Images push to
   `ghcr.io/<owner>/cuevolution` as *private* by default. Either:
   - Make the package public (Package settings on GitHub → Change visibility) — simplest, fine if the source isn't sensitive, or
   - `docker login ghcr.io` on the server with a [PAT](https://github.com/settings/tokens)
     that has `read:packages` scope.

## GitHub configuration

Create two [GitHub Environments](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment)
named `staging` and `production` (Settings → Environments), each with its
own value for the same four secret names:

| Secret             | Value                                                   |
| ------------------- | -------------------------------------------------------- |
| `SSH_HOST`          | The server's IP or hostname — **the same value in both environments**, since it's one server |
| `SSH_USER`          | The deploy user created above — also the same in both   |
| `SSH_PRIVATE_KEY`   | Contents of `deploy_key` (the private key, not `.pub`)  |
| `SSH_PORT`          | Usually `22`                                             |

Keeping them as two separate GitHub Environments (even though the values
largely overlap) is still worth it — it's what lets you attach different
protection rules later (e.g. required reviewers before a production
deploy) without restructuring the workflows.

No GHCR secret is needed — the workflows push using the automatically
provided `GITHUB_TOKEN` (with `packages: write` permission set in the
workflow itself).

Optionally, add branch protection on `main` (and `develop` if desired)
requiring the `CI` workflow to pass before merging — this repo's workflow
files alone can't turn that on; it's a Settings → Branches rule.

## Rolling back

Each deploy is tagged with its commit SHA (`staging-<sha>` /
`production-<sha>`), not just the floating `staging`/`production` tag. To
roll back, SSH in and point that environment's `.env` at an older tag:

```
cd /opt/cuevolution-production   # or -staging
sed -i "s|^IMAGE=.*|IMAGE=ghcr.io/<owner>/cuevolution:production-<old-sha>|" .env
docker compose --env-file .env up -d
```

(Skip re-running migrations on rollback unless you're also reverting the
schema — `bin/migrate` is idempotent but a *down* migration needs
`bin/cuevolution eval "Cuevolution.Release.rollback(Cuevolution.Repo, <version>)"`
run manually.)

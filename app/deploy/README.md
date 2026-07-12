# Deployment

Two long-lived branches, two servers, two environments:

| Branch    | Workflow                                            | Environment  |
| --------- | ---------------------------------------------------- | ------------ |
| `develop` | `.github/workflows/deploy-staging.yml`               | `staging`    |
| `main`    | `.github/workflows/deploy-production.yml`            | `production` |

Every pull request (regardless of target branch) also runs `.github/workflows/ci.yml`
— format check, `mix compile --warnings-as-errors`, `mix credo --strict`,
`mix test`. Both deploy workflows run the same checks (via the shared
`.github/workflows/test.yml`) before building or deploying anything, so a
broken `develop`/`main` push never reaches a server even if branch
protection isn't configured.

On push, the deploy workflow builds the Docker image from `app/Dockerfile`,
pushes it to GHCR, copies `app/deploy/docker-compose.yml` and
`app/deploy/Caddyfile` to the server, then SSHes in to pull the new image,
run migrations, and restart the stack.

Note: `.github/workflows/` lives at the repo root, one level up from this
`app/` directory, even though everything else deploy-related is in here —
GitHub only ever looks for workflows at the repository root.

## One-time setup per server

Do this once for staging, once for production (different host, same steps).

1. **Install Docker.** Follow [Docker's install guide](https://docs.docker.com/engine/install/)
   for your distro; the `docker compose` plugin (v2, not the standalone
   `docker-compose` binary) needs to be present — check with
   `docker compose version`.

2. **Create a deploy user** (or reuse an existing one) that's in the
   `docker` group, and generate an SSH keypair for GitHub Actions to use:

   ```
   ssh-keygen -t ed25519 -f deploy_key -N ""
   ```

   Add `deploy_key.pub` to that user's `~/.ssh/authorized_keys` on the
   server. `deploy_key` (the private half) becomes the `SSH_PRIVATE_KEY`
   secret below — never commit it.

3. **Create a Backblaze B2 bucket for this environment** (a separate
   bucket per environment — don't share one between staging and
   production). It must be **public** — profile pictures aren't sensitive,
   and the app returns a plain public URL rather than a signed one (see
   `lib/cuevolution/accounts/profile_picture/storage/backblaze.ex`).
   Create an Application Key scoped to that bucket, and note the bucket's
   "Endpoint" (e.g. `s3.us-west-004.backblazeb2.com`) from its details page.

4. **Create the app directory and env file:**

   ```
   sudo mkdir -p /opt/cuevolution
   sudo chown $(whoami) /opt/cuevolution
   ```

   Copy `app/deploy/.env.example` from this repo to `/opt/cuevolution/.env`
   on the server and fill in real values (`POSTGRES_PASSWORD`, `SECRET_KEY_BASE`
   — generate with `mix phx.gen.secret` — `DOMAIN`, `CADDY_EMAIL`, the
   `BACKBLAZE_*` values from step 3, and whichever SMS provider you're
   using). This file is **never** touched by CI except for its `IMAGE=`
   line, and never leaves the server.

5. **Point DNS** for the environment's domain at the server's IP —
   required before Caddy can obtain a Let's Encrypt certificate.

6. **Make the GHCR package pullable from the server.** Images push to
   `ghcr.io/<owner>/cuevolution` as *private* by default. Either:
   - Make the package public (Package settings on GitHub → Change visibility) — simplest, fine if the source isn't sensitive, or
   - `docker login ghcr.io` on the server with a [PAT](https://github.com/settings/tokens)
     that has `read:packages` scope.

7. **First deploy is manual**, since `docker-compose.yml`/`.env` don't
   exist on the server until step 4 and the app needs *a* image reference
   before the workflow's `sed` can update it:

   ```
   cd /opt/cuevolution
   echo "IMAGE=ghcr.io/<owner>/cuevolution:staging" >> .env   # or :production
   docker compose --env-file .env pull
   docker compose --env-file .env run --rm app bin/migrate
   docker compose --env-file .env up -d
   ```

   After this, pushes to `develop`/`main` handle everything automatically.

## GitHub configuration

Create two [GitHub Environments](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment)
named `staging` and `production` (Settings → Environments), each with its
own value for the same four secret names — this is what lets both deploy
workflows reference `secrets.SSH_HOST` etc. and still hit the right server:

| Secret            | Value                                                        |
| ------------------ | ------------------------------------------------------------ |
| `SSH_HOST`         | Server IP or hostname                                        |
| `SSH_USER`         | The deploy user created above                                |
| `SSH_PRIVATE_KEY`  | Contents of `deploy_key` (the private key, not `.pub`)       |
| `SSH_PORT`         | Usually `22`                                                 |

No GHCR secret is needed — the workflows push using the automatically
provided `GITHUB_TOKEN` (with `packages: write` permission set in the
workflow itself).

Optionally, add branch protection on `main` (and `develop` if desired)
requiring the `CI` workflow to pass before merging — this repo's workflow
files alone can't turn that on; it's a Settings → Branches rule.

## Rolling back

Each deploy is tagged with its commit SHA (`staging-<sha>` /
`production-<sha>`), not just the floating `staging`/`production` tag. To
roll back, SSH in and point `.env` at an older tag:

```
cd /opt/cuevolution
sed -i "s|^IMAGE=.*|IMAGE=ghcr.io/<owner>/cuevolution:production-<old-sha>|" .env
docker compose --env-file .env up -d
```

(Skip re-running migrations on rollback unless you're also reverting the
schema — `bin/migrate` is idempotent but a *down* migration needs
`bin/cuevolution eval "Cuevolution.Release.rollback(Cuevolution.Repo, <version>)"`
run manually.)

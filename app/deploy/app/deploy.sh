#!/bin/bash
# Run from /opt/cuevolution-production on the VM (see deploy/README.md).
# Usage: ./deploy.sh [IMAGE_TAG]
#
# Fetches DATABASE_URL and CUEVOLUTION_SECRETS_JSON fresh from Secret
# Manager on every run — the same secrets Cloud Run's --set-secrets reads,
# just pulled via this VM's attached service account instead (no key file,
# same mechanism cloud-sql-proxy and the app's own GCS auth already use).
# Nothing secret is written to .env on disk; these two only ever live in
# this script's process environment, picked up by docker compose's variable
# substitution when it runs in the same shell.
set -euo pipefail
cd "$(dirname "$0")"

if [ -n "${1:-}" ]; then
  sed -i "s|^IMAGE=.*|IMAGE=$1|" .env
fi

export CUEVOLUTION_SECRETS_JSON="$(gcloud secrets versions access latest --secret=cuevolution-production-application-secrets)"
export DATABASE_URL="$(gcloud secrets versions access latest --secret=cuevolution-production-vm-database-url)"

docker compose --env-file .env pull

# Stop the running app/worker before migrating: db-f1-micro's small
# connection ceiling (~25) can't fit their existing pools (POOL_SIZE each)
# plus a migration run on top of that — this took production down twice
# before this fix (too_many_connections). This does mean a brief gap
# with nothing serving traffic during a routine deploy — there's no
# blue-green here, only the one-time Cloud Run cutover was built for zero
# downtime, not ongoing deploys.
docker compose --env-file .env stop app worker

# The migration process only needs a couple of connections, not a full
# pool — same POOL_SIZE=2 override Cloud Run's migration job used.
docker compose --env-file .env run --rm -e POOL_SIZE=2 app bin/migrate

docker compose --env-file .env up -d

# Port 4000 is deliberately not published to the host (only reachable on the
# "web" Docker network, which is how Caddy reaches it) — so the smoke test
# has to run inside the app container itself, not against host localhost.
for i in $(seq 1 10); do
  if docker compose --env-file .env exec -T app wget -qO- http://localhost:4000/health/readiness; then
    exit 0
  fi
  sleep 3
done
echo "app did not become healthy in time" >&2
exit 1

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
docker compose --env-file .env run --rm app bin/migrate
docker compose --env-file .env up -d
curl --fail --silent --show-error --retry 5 --retry-delay 5 http://localhost:4000/health/readiness

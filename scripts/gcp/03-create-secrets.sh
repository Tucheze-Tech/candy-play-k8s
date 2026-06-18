#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="candy-play"

echo "==> Setting gcloud project to: $PROJECT_ID"
gcloud config set project "$PROJECT_ID"

echo "==> Ensuring Redis shared secret..."
# Reuse the existing password if the secret already exists — regenerating would
# desync an already-running Redis pod from this secret. Only mint on first run.
if gcloud secrets describe candyplay_shared_redis --project="$PROJECT_ID" >/dev/null 2>&1; then
  REDIS_PASSWORD=$(gcloud secrets versions access latest \
    --secret=candyplay_shared_redis --project="$PROJECT_ID" \
    | python3 -c 'import sys,json;print(json.load(sys.stdin)["REDIS_PASSWORD"])')
  echo "  Secret candyplay_shared_redis exists — reusing stored password."
else
  REDIS_PASSWORD=$(openssl rand -base64 24)
  echo "{\"REDIS_HOST\": \"redis.candy-services.svc.cluster.local\", \"REDIS_PORT\": \"6379\", \"REDIS_PASSWORD\": \"${REDIS_PASSWORD}\"}" \
    | gcloud secrets create candyplay_shared_redis \
        --project="$PROJECT_ID" \
        --data-file=- \
        --replication-policy=automatic
  echo "  Redis secret created: candyplay_shared_redis"
fi

echo ""
echo "==> Ensuring Cloudflare API token secret (for cert-manager DNS-01)..."
# Raw token string. Create empty-ish if absent; fill the real token before 05:
#   printf 'YOUR_CF_TOKEN' | gcloud secrets versions add cloudflare_api_token --data-file=-
# Scope: Zone.DNS Edit + Zone Read on the candyplay.co.ke zone.
if gcloud secrets describe cloudflare_api_token --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "  cloudflare_api_token already exists — skipping (value preserved)."
else
  printf 'CHANGEME' | gcloud secrets create cloudflare_api_token \
    --project="$PROJECT_ID" --data-file=- --replication-policy=automatic
  echo "  Created cloudflare_api_token (placeholder CHANGEME — set the real token before 05)."
fi

echo ""
echo "==> Cutover: convert legacy .env-string secrets to flat JSON (idempotent)..."
# The unified ESO pattern needs each secret to be flat JSON {"KEY":"value",...}.
# gonga_prd_settings + tpay_settings historically held a single .env string.
# This converts them and seeds an in-cluster DATABASE_URL (cloud-sql-proxy at
# 127.0.0.1) from the per-service DB creds. SAFE: a new version is added only
# when the current payload is NOT already a JSON object — the old version is
# always retained, so the cutover is reversible (disable the new version).
declare -A CUTOVER_MAP
CUTOVER_MAP["gonga_prd_settings"]="icore_db_credentials"
CUTOVER_MAP["tpay_settings"]="tpay_db_credentials"

for secret in gonga_prd_settings tpay_settings; do
  if ! gcloud secrets describe "$secret" --project="$PROJECT_ID" >/dev/null 2>&1; then
    echo "  WARN: $secret not found — skipping cutover."
    continue
  fi
  raw=$(gcloud secrets versions access latest --secret="$secret" --project="$PROJECT_ID")
  db_secret="${CUTOVER_MAP[$secret]}"
  db_json=""
  if gcloud secrets describe "$db_secret" --project="$PROJECT_ID" >/dev/null 2>&1; then
    db_json=$(gcloud secrets versions access latest --secret="$db_secret" --project="$PROJECT_ID")
  else
    echo "  WARN: $db_secret missing — converting $secret WITHOUT seeding DATABASE_URL."
  fi
  new=$(DB_JSON="$db_json" python3 - "$raw" <<'PY'
import json, os, sys
from urllib.parse import quote
raw = sys.argv[1]
# Already flat JSON object? -> emit nothing so the caller skips re-versioning.
try:
    if isinstance(json.loads(raw), dict):
        sys.exit(0)
except (ValueError, TypeError):
    pass
# Parse the legacy .env string into a flat dict.
out = {}
for line in raw.splitlines():
    line = line.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    k, v = line.split("=", 1)
    out[k.strip()] = v.strip().strip('"').strip("'")
# Seed an in-cluster DATABASE_URL from DB creds (proxy listens on 127.0.0.1).
dbj = os.environ.get("DB_JSON", "")
if dbj:
    db = json.loads(dbj)
    pw = quote(db["DB_PASSWORD"], safe="")
    out["DATABASE_URL"] = f"postgresql://{db['DB_USER']}:{pw}@{db['DB_HOST']}:{db['DB_PORT']}/{db['DB_NAME']}"
print(json.dumps(out))
PY
)
  if [ -z "$new" ]; then
    echo "  $secret already flat JSON — no cutover needed."
  else
    printf '%s' "$new" | gcloud secrets versions add "$secret" \
      --project="$PROJECT_ID" --data-file=-
    echo "  $secret converted to flat JSON (new version added; old retained)."
  fi
done
echo ""
echo "==> Ensuring new ESO settings secrets (flat JSON) for ev + 01-tech..."
# Created ONLY if absent — a re-run never clobbers real values added later.
# DATABASE_URL is seeded from the per-service DB creds minted in 02; everything
# else is a placeholder to be filled in (gcloud secrets versions add ...).
# ev_prd_settings   <- ev_db_credentials
# 01tech_prd_settings <- 01tech_db_credentials
declare -A SETTINGS_MAP
SETTINGS_MAP["ev_prd_settings"]="ev_db_credentials"
SETTINGS_MAP["01tech_prd_settings"]="01tech_db_credentials"

# extra placeholder keys per settings secret (space-separated)
declare -A EXTRA_KEYS
EXTRA_KEYS["ev_prd_settings"]="ICORE_URL ICORE_API_KEY EV_APP_API_KEY"
EXTRA_KEYS["01tech_prd_settings"]="ICORE_URL INTERNAL_API_KEY"

for secret in ev_prd_settings 01tech_prd_settings; do
  if gcloud secrets describe "$secret" --project="$PROJECT_ID" >/dev/null 2>&1; then
    echo "  $secret already exists — skipping (values preserved)."
    continue
  fi
  db_secret="${SETTINGS_MAP[$secret]}"
  if ! gcloud secrets describe "$db_secret" --project="$PROJECT_ID" >/dev/null 2>&1; then
    echo "  WARN: $db_secret not found (run 02-create-cloudsql.sh first) — skipping $secret."
    continue
  fi
  db_json=$(gcloud secrets versions access latest --secret="$db_secret" --project="$PROJECT_ID")
  json=$(EXTRA="${EXTRA_KEYS[$secret]}" python3 - "$db_json" <<'PY'
import json, os, sys
from urllib.parse import quote
db = json.loads(sys.argv[1])
pw = quote(db["DB_PASSWORD"], safe="")  # base64 pw may contain + / = -> must encode
out = {
    "DATABASE_URL": f"postgresql://{db['DB_USER']}:{pw}@{db['DB_HOST']}:{db['DB_PORT']}/{db['DB_NAME']}",
}
for k in os.environ.get("EXTRA", "").split():
    out[k] = "CHANGEME"
print(json.dumps(out))
PY
)
  printf '%s' "$json" | gcloud secrets create "$secret" \
    --project="$PROJECT_ID" --data-file=- --replication-policy=automatic
  echo "  Created $secret (DATABASE_URL seeded; placeholders = CHANGEME — fill before go-live)."
done
echo ""
echo "==> Create Redis K8s secret (for the Redis pod itself)..."
kubectl create secret generic redis-secret \
  --namespace=candy-services \
  --from-literal=password="$REDIS_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Done. Redis password: $REDIS_PASSWORD (also stored in GCP Secret Manager: candyplay_shared_redis)"

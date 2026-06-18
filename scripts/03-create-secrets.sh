#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="cm-services-prod"

echo "==> Creating Redis shared secret..."
REDIS_PASSWORD=$(openssl rand -base64 24)
echo "{\"REDIS_HOST\": \"redis.candy-services.svc.cluster.local\", \"REDIS_PORT\": \"6379\", \"REDIS_PASSWORD\": \"${REDIS_PASSWORD}\"}" \
  | gcloud secrets create candyplay_shared_redis \
      --project="$PROJECT_ID" \
      --data-file=- \
      --replication-policy=automatic \
  2>/dev/null || \
echo "{\"REDIS_HOST\": \"redis.candy-services.svc.cluster.local\", \"REDIS_PORT\": \"6379\", \"REDIS_PASSWORD\": \"${REDIS_PASSWORD}\"}" \
  | gcloud secrets versions add candyplay_shared_redis \
      --project="$PROJECT_ID" \
      --data-file=-

echo "  Redis secret created: candyplay_shared_redis"

echo ""
echo "==> IMPORTANT: Update the following existing secrets to add K8s-compatible DATABASE_URL:"
echo "  - gonga_prd_settings : add DATABASE_URL=postgresql://icore_user:<password>@127.0.0.1:5432/icore_prod"
echo "  - tpay_settings      : add DATABASE_URL=postgresql://tpay_user:<password>@127.0.0.1:5432/tpay_prod"
echo ""
echo "==> Create new secrets for services not yet in Secret Manager:"
echo "  ev_prd_settings  (JSON with DATABASE_URL, ICORE_URL, ICORE_API_KEY, EV_APP_API_KEY, etc.)"
echo "  01tech_prd_settings (JSON with DATABASE_URL, INTERNAL_API_KEY, ICORE_URL, etc.)"
echo ""
echo "==> Create Redis K8s secret (for the Redis pod itself)..."
kubectl create secret generic redis-secret \
  --namespace=candy-services \
  --from-literal=password="$REDIS_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Done. Redis password: $REDIS_PASSWORD (also stored in GCP Secret Manager: candyplay_shared_redis)"

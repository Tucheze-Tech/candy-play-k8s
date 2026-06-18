#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="candy-play"
CLUSTER_NAME="candyplay-prod"

echo "==> Setting gcloud project to: $PROJECT_ID"
gcloud config set project "$PROJECT_ID"

# GSA account IDs must be 6-30 chars AND start with a letter, so two services
# can't use the naive "<svc>-sa": euro-virtuals (too short) and 01tech (leading
# digit). Map svc token -> GSA account id explicitly.
declare -A GSA
GSA["icore"]="icore-sa"
GSA["euro-virtuals"]="euro-virtuals-sa"
GSA["tpay"]="tpay-sa"
GSA["01tech"]="tech01-sa"
GSA["external-secrets"]="external-secrets-sa"
GSA["metabase"]="metabase-sa"
GSA["grafana"]="grafana-sa"

SERVICES=("icore" "euro-virtuals" "tpay" "01tech" "external-secrets" "metabase" "grafana")

gsa_email() { echo "${GSA[$1]}@${PROJECT_ID}.iam.gserviceaccount.com"; }

echo "==> Creating GCP Service Accounts..."
for svc in "${SERVICES[@]}"; do
  SA_EMAIL="$(gsa_email "$svc")"
  if gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT_ID" >/dev/null 2>&1; then
    echo "  ${GSA[$svc]} already exists — skipping."
  else
    echo "  Creating: ${GSA[$svc]}"
    gcloud iam service-accounts create "${GSA[$svc]}" \
      --project="$PROJECT_ID" \
      --display-name="K8s SA for $svc"
  fi
done

# IAM SA creation is eventually consistent — add-iam-policy-binding can fail with
# "does not exist" if it runs before the SA propagates. Wait until all are visible.
echo "==> Waiting for service accounts to propagate..."
for svc in "${SERVICES[@]}"; do
  SA_EMAIL="$(gsa_email "$svc")"
  for i in $(seq 1 30); do
    gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT_ID" >/dev/null 2>&1 && break
    [ "$i" -eq 30 ] && { echo "  ERROR: $SA_EMAIL not visible after ~150s" >&2; exit 1; }
    sleep 5
  done
done
echo "  All service accounts visible."

echo "==> Granting Cloud SQL Client role..."
for svc in icore euro-virtuals tpay 01tech metabase grafana; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$(gsa_email "$svc")" \
    --role="roles/cloudsql.client" \
    --condition=None
done

echo "==> Granting Secret Manager Accessor role..."
for svc in icore euro-virtuals tpay 01tech external-secrets metabase; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$(gsa_email "$svc")" \
    --role="roles/secretmanager.secretAccessor" \
    --condition=None
done

echo "==> Binding GCP SAs to K8s SAs via Workload Identity..."

# App services in candy-services namespace
declare -A KSA_MAP
KSA_MAP["icore"]="icore-ksa"
KSA_MAP["euro-virtuals"]="ev-ksa"
KSA_MAP["tpay"]="tpay-ksa"
KSA_MAP["01tech"]="01tech-ksa"

for svc in icore euro-virtuals tpay 01tech; do
  KSA="${KSA_MAP[$svc]}"
  GCP_SA="$(gsa_email "$svc")"
  MEMBER="serviceAccount:${PROJECT_ID}.svc.id.goog[candy-services/${KSA}]"

  gcloud iam service-accounts add-iam-policy-binding "$GCP_SA" \
    --project="$PROJECT_ID" \
    --role="roles/iam.workloadIdentityUser" \
    --member="$MEMBER" \
    --condition=None

  echo "  Bound: $GCP_SA -> $MEMBER"
done

# External Secrets Operator
gcloud iam service-accounts add-iam-policy-binding \
  "external-secrets-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
  --project="$PROJECT_ID" \
  --role="roles/iam.workloadIdentityUser" \
  --member="serviceAccount:${PROJECT_ID}.svc.id.goog[external-secrets/external-secrets-ksa]" \
    --condition=None

# Metabase (cloud-sql-proxy sidecar needs Workload Identity)
# pmint93 chart creates SA named "metabase" in the metabase namespace
gcloud iam service-accounts add-iam-policy-binding \
  "metabase-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
  --project="$PROJECT_ID" \
  --role="roles/iam.workloadIdentityUser" \
  --member="serviceAccount:${PROJECT_ID}.svc.id.goog[metabase/metabase]" \
    --condition=None

# Grafana (cloud-sql-proxy sidecar needs Workload Identity)
# values.yaml pins grafana.serviceAccount.name=grafana in the monitoring namespace
gcloud iam service-accounts add-iam-policy-binding \
  "grafana-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
  --project="$PROJECT_ID" \
  --role="roles/iam.workloadIdentityUser" \
  --member="serviceAccount:${PROJECT_ID}.svc.id.goog[monitoring/grafana]" \
    --condition=None

echo "==> Workload Identity bindings complete."
echo ""
echo "==> Next: Install Helm charts (see scripts/gcp/05-bootstrap-helm.sh)"

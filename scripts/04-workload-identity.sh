#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="cm-services-prod"
CLUSTER_NAME="candyplay-prod"

SERVICES=("icore" "ev" "tpay" "01tech" "external-secrets" "metabase")

echo "==> Creating GCP Service Accounts..."
for svc in "${SERVICES[@]}"; do
  SA_NAME="${svc}-sa"
  echo "  Creating: $SA_NAME"
  gcloud iam service-accounts create "$SA_NAME" \
    --project="$PROJECT_ID" \
    --display-name="K8s SA for $svc" \
    2>/dev/null || echo "  (already exists, skipping)"
done

echo "==> Granting Cloud SQL Client role..."
for svc in icore ev tpay 01tech metabase; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${svc}-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/cloudsql.client"
done

echo "==> Granting Secret Manager Accessor role..."
for svc in icore ev tpay 01tech external-secrets metabase; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${svc}-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor"
done

echo "==> Binding GCP SAs to K8s SAs via Workload Identity..."

# App services in candy-services namespace
declare -A KSA_MAP
KSA_MAP["icore"]="icore-ksa"
KSA_MAP["ev"]="ev-ksa"
KSA_MAP["tpay"]="tpay-ksa"
KSA_MAP["01tech"]="01tech-ksa"

for svc in icore ev tpay 01tech; do
  KSA="${KSA_MAP[$svc]}"
  GCP_SA="${svc}-sa@${PROJECT_ID}.iam.gserviceaccount.com"
  MEMBER="serviceAccount:${PROJECT_ID}.svc.id.goog[candy-services/${KSA}]"

  gcloud iam service-accounts add-iam-policy-binding "$GCP_SA" \
    --project="$PROJECT_ID" \
    --role="roles/iam.workloadIdentityUser" \
    --member="$MEMBER"

  echo "  Bound: $GCP_SA -> $MEMBER"
done

# External Secrets Operator
gcloud iam service-accounts add-iam-policy-binding \
  "external-secrets-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
  --project="$PROJECT_ID" \
  --role="roles/iam.workloadIdentityUser" \
  --member="serviceAccount:${PROJECT_ID}.svc.id.goog[external-secrets/external-secrets-ksa]"

# Metabase (cloud-sql-proxy sidecar needs Workload Identity)
# pmint93 chart creates SA named "metabase" in the metabase namespace
gcloud iam service-accounts add-iam-policy-binding \
  "metabase-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
  --project="$PROJECT_ID" \
  --role="roles/iam.workloadIdentityUser" \
  --member="serviceAccount:${PROJECT_ID}.svc.id.goog[metabase/metabase]"

echo "==> Workload Identity bindings complete."
echo ""
echo "==> Next: Install Helm charts (see scripts/05-bootstrap-helm.sh)"

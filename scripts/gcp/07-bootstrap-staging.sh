#!/usr/bin/env bash
# Bootstrap the staging namespace inside the same GKE cluster.
# Run AFTER 05-bootstrap-helm.sh (Kong, cert-manager, ESO must already be installed).
set -euo pipefail

# Resolve relative paths from the k8s repo root regardless of invocation dir.
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

PROJECT_ID="candy-play"
REGION="europe-west3"
CLUSTER_NAME="candyplay-prod"

gcloud container clusters get-credentials "$CLUSTER_NAME" \
  --region="$REGION" --project="$PROJECT_ID"

echo "==> Creating staging namespace..."
kubectl create namespace candy-services-staging --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace candy-services-staging monitoring=true --overwrite

echo "==> Creating staging Cloud SQL databases..."
for db in icore_staging ev_staging tpay_staging 01tech_staging; do
  gcloud sql databases create "$db" \
    --instance=candyplay-prod-pg \
    --project="$PROJECT_ID" \
    2>/dev/null || echo "  $db already exists"
done

echo "==> Creating staging GCP secrets (update content manually)..."
for svc in gonga_stg_settings ev_stg_settings tpay_stg_settings 01tech_stg_settings; do
  gcloud secrets create "$svc" \
    --project="$PROJECT_ID" \
    --replication-policy=automatic \
    2>/dev/null || echo "  $svc already exists"
  echo "  --> Populate: gcloud secrets versions add $svc --data-file=<your-staging-env-file>"
done

echo "==> Binding Workload Identity for staging SAs..."
# GSA id and KSA name diverge: GSA ids must start with a letter and be >=6 chars,
# so euro-virtuals->euro-virtuals-sa and 01tech->tech01-sa, while the staging KSAs
# stay <svc>-ksa-stg. Map both explicitly. (Staging shares the prod GSAs.)
declare -A GSA
GSA["icore"]="icore-sa"
GSA["euro-virtuals"]="euro-virtuals-sa"
GSA["tpay"]="tpay-sa"
GSA["01tech"]="tech01-sa"
declare -A STG_KSA
STG_KSA["icore"]="icore-ksa-stg"
STG_KSA["euro-virtuals"]="ev-ksa-stg"
STG_KSA["tpay"]="tpay-ksa-stg"
STG_KSA["01tech"]="01tech-ksa-stg"
for svc in icore euro-virtuals tpay 01tech; do
  gcloud iam service-accounts add-iam-policy-binding \
    "${GSA[$svc]}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --project="$PROJECT_ID" \
    --role="roles/iam.workloadIdentityUser" \
    --member="serviceAccount:${PROJECT_ID}.svc.id.goog[candy-services-staging/${STG_KSA[$svc]}]" \
    --condition=None
done

# Staging Kong plugins/consumer are now Helm-owned (candy-common.kong, rendered
# from each chart's values-staging.yaml) — no separate manifest to apply.

echo "==> Applying staging TLS certificate..."
kubectl apply -f infrastructure/cert-manager/clusterissuer-staging.yaml

echo "==> Staging namespace ready."
echo "    Next: run scripts/common/deploy-services.sh staging gke"

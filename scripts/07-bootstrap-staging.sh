#!/usr/bin/env bash
# Bootstrap the staging namespace inside the same GKE cluster.
# Run AFTER 05-bootstrap-helm.sh (Kong, cert-manager, ESO must already be installed).
set -euo pipefail

PROJECT_ID="cm-services-prod"
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
for svc in icore ev tpay 01tech; do
  gcloud iam service-accounts add-iam-policy-binding \
    "${svc}-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
    --project="$PROJECT_ID" \
    --role="roles/iam.workloadIdentityUser" \
    --member="serviceAccount:${PROJECT_ID}.svc.id.goog[candy-services-staging/${svc}-ksa-stg]" \
    2>/dev/null || true
done

echo "==> Applying staging Kong plugins..."
kubectl apply -f infrastructure/kong/staging-plugins.yaml

echo "==> Applying staging TLS certificate..."
kubectl apply -f infrastructure/cert-manager/clusterissuer-staging.yaml

echo "==> Staging namespace ready."
echo "    Next: run 06-deploy-services.sh staging"

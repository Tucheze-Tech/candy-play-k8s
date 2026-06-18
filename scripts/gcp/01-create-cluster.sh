#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="candy-play"
REGION="europe-west3"
CLUSTER_NAME="candyplay-prod"

echo "==> Setting gcloud project to: $PROJECT_ID"
gcloud config set project candy-play

echo "==> Enabling required APIs..."
gcloud services enable \
  container.googleapis.com \
  sqladmin.googleapis.com \
  secretmanager.googleapis.com \
  artifactregistry.googleapis.com \
  servicenetworking.googleapis.com \
  --project="$PROJECT_ID"

if gcloud container clusters describe "$CLUSTER_NAME" \
     --region="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "==> Cluster $CLUSTER_NAME already exists — skipping create."
else
  echo "==> Creating GKE Autopilot cluster: $CLUSTER_NAME..."
  gcloud container clusters create-auto "$CLUSTER_NAME" \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    --release-channel=regular \
    --network=default \
    --subnetwork=default \
    --enable-private-nodes \
    --master-ipv4-cidr=172.16.0.0/28 \
    --logging=SYSTEM,WORKLOAD \
    --monitoring=SYSTEM
fi

# Private nodes have no public egress — without Cloud NAT they cannot pull
# public images (cert-manager/quay.io, Kong, Grafana, etc). Idempotent.
echo "==> Ensuring Cloud NAT for private-node egress..."
if ! gcloud compute routers describe candyplay-nat-router \
       --region="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud compute routers create candyplay-nat-router \
    --region="$REGION" --network=default --project="$PROJECT_ID"
fi
if ! gcloud compute routers nats describe candyplay-nat \
       --router=candyplay-nat-router --region="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud compute routers nats create candyplay-nat \
    --router=candyplay-nat-router --region="$REGION" \
    --auto-allocate-nat-external-ips --nat-all-subnet-ip-ranges \
    --project="$PROJECT_ID"
fi

echo "==> Getting credentials..."
gcloud container clusters get-credentials "$CLUSTER_NAME" \
  --region="$REGION" \
  --project="$PROJECT_ID"

echo "==> Creating namespaces..."
kubectl create namespace candy-services --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace kong --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace metabase --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -

echo "==> Labeling namespaces for Prometheus scraping..."
kubectl label namespace candy-services monitoring=true --overwrite
kubectl label namespace kong monitoring=true --overwrite

echo "==> Cluster ready: $CLUSTER_NAME"

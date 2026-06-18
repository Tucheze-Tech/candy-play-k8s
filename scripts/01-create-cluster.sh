#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="cm-services-prod"
REGION="europe-west3"
CLUSTER_NAME="candyplay-prod"

echo "==> Enabling required APIs..."
gcloud services enable \
  container.googleapis.com \
  sqladmin.googleapis.com \
  secretmanager.googleapis.com \
  artifactregistry.googleapis.com \
  servicenetworking.googleapis.com \
  --project="$PROJECT_ID"

echo "==> Creating GKE Autopilot cluster: $CLUSTER_NAME..."
gcloud container clusters create-auto "$CLUSTER_NAME" \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --release-channel=regular \
  --network=default \
  --subnetwork=default \
  --enable-private-nodes \
  --master-ipv4-cidr=172.16.0.0/28 \
  --workload-pool="${PROJECT_ID}.svc.id.goog" \
  --enable-shielded-nodes \
  --logging=SYSTEM,WORKLOAD \
  --monitoring=SYSTEM

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

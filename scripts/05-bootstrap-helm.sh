#!/usr/bin/env bash
set -euo pipefail

echo "==> Adding Helm repos..."
helm repo add jetstack https://charts.jetstack.io
helm repo add external-secrets https://charts.external-secrets.io
helm repo add kong https://charts.konghq.com
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add pmint93 https://pmint93.github.io/helm-charts
helm repo update

echo ""
echo "==> [1/7] Installing cert-manager..."
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true \
  --version v1.16.3

kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/instance=cert-manager \
  -n cert-manager --timeout=120s

kubectl apply -f infrastructure/cert-manager/clusterissuer.yaml

echo ""
echo "==> [2/7] Installing External Secrets Operator..."
helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --set serviceAccount.annotations."iam\.gke\.io/gcp-service-account"="external-secrets-sa@cm-services-prod.iam.gserviceaccount.com" \
  --version 0.10.5

kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/instance=external-secrets \
  -n external-secrets --timeout=120s

kubectl apply -f infrastructure/external-secrets/clustersecretstore.yaml

echo ""
echo "==> [3/7] Creating Kong namespace and DB secret..."
kubectl create namespace kong --dry-run=client -o yaml | kubectl apply -f -
# ESO pulls kong_db_credentials from GCP Secret Manager → kong-db-secret
kubectl apply -f infrastructure/kong/db-externalsecret.yaml

echo "  Waiting for kong-db-secret to sync (ESO needs ~30s)..."
sleep 35
kubectl wait externalsecret/kong-db-secret -n kong \
  --for=condition=Ready --timeout=60s

echo ""
echo "==> [4/7] Installing Kong Ingress Controller (PostgreSQL mode)..."
helm upgrade --install kong kong/kong \
  --namespace kong \
  --create-namespace \
  -f infrastructure/kong/values.yaml \
  --version 2.38.0

kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/instance=kong \
  -n kong --timeout=300s

echo ""
echo "==> Kong LB IP (point api.candyplay.com AND api-dev.candyplay.com DNS here):"
kubectl get svc -n kong kong-kong-proxy \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
echo ""
echo "  --> Update DNS for BOTH domains before continuing! Press ENTER when ready..."
read -r

echo ""
echo "==> [5/7] Deploying Redis..."
kubectl create namespace candy-services --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f infrastructure/redis/pvc.yaml
kubectl apply -f infrastructure/redis/deployment.yaml
kubectl apply -f infrastructure/redis/service.yaml

echo ""
echo "==> [6/7] Installing Grafana + Prometheus + Loki..."
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  -f infrastructure/monitoring/values.yaml \
  --version 65.3.1

# Loki stack (Loki + Promtail DaemonSet for log collection)
helm upgrade --install loki grafana/loki-stack \
  --namespace monitoring \
  -f infrastructure/loki/values.yaml \
  --version 2.10.2

kubectl label namespace monitoring monitoring=true --overwrite

echo ""
echo "==> [7/7] Installing Metabase..."
kubectl create namespace metabase --dry-run=client -o yaml | kubectl apply -f -
# ESO pulls metabase_db_credentials from GCP SM → metabase-db-secret
kubectl apply -f infrastructure/metabase/externalsecret.yaml

echo "  Waiting for metabase-db-secret to sync..."
sleep 20
kubectl wait externalsecret/metabase-db-secret -n metabase \
  --for=condition=Ready --timeout=60s

helm upgrade --install metabase pmint93/metabase \
  --namespace metabase \
  --create-namespace \
  -f infrastructure/metabase/values.yaml

echo ""
echo "==> Infrastructure bootstrap complete."
echo ""
echo "==> URLs (after DNS propagates):"
echo "    Grafana  : https://api.candyplay.com/grafana    (default user: admin)"
echo "    Metabase : https://api.candyplay.com/metabase"
echo "    Kong Admin API (internal only): kubectl port-forward -n kong svc/kong-kong-admin 8001:8001"
echo ""
echo "==> Grafana admin password:"
kubectl get secret -n monitoring monitoring-grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d
echo ""
echo ""
echo "==> Next: Deploy app services with 06-deploy-services.sh"

#!/usr/bin/env bash
set -euo pipefail

ENV="${1:-production}"

if [ "$ENV" = "staging" ]; then
  NAMESPACE="candy-services-staging"
  RELEASE_SUFFIX="-stg"
else
  NAMESPACE="candy-services"
  RELEASE_SUFFIX=""
fi

echo "==> Deploying all services (env: $ENV, namespace: $NAMESPACE)..."

for svc in icore euro-virtuals tpay 01-tech; do
  RELEASE="${svc}${RELEASE_SUFFIX}"
  echo ""
  echo "==> Deploying $RELEASE..."
  helm upgrade --install "$RELEASE" "charts/$svc/" \
    --namespace "$NAMESPACE" \
    --create-namespace \
    -f "charts/$svc/values.yaml" \
    -f "charts/$svc/values-${ENV}.yaml"
done

echo ""
echo "==> Waiting for pods..."
kubectl wait --for=condition=ready pod \
  -l "app.kubernetes.io/name in (icore,euro-virtuals)" \
  -n "$NAMESPACE" --timeout=300s

echo ""
echo "==> Pods:"
kubectl get pods -n "$NAMESPACE"

echo ""
echo "==> ExternalSecrets:"
kubectl get externalsecret -n "$NAMESPACE"

echo ""
echo "==> Ingress routes:"
kubectl get ingress -n "$NAMESPACE"

#!/usr/bin/env bash
# Deploy all 4 app services to the CURRENT kubectl context.
# Cloud-agnostic: works on GKE or EKS — the cloud overlay decides the specifics.
#
#   ./scripts/common/deploy-services.sh [production|staging] [gke|eks]
#
# Chart paths are relative; resolved from the k8s repo root automatically.
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

ENV="${1:-production}"
CLOUD="${2:-gke}"

if [ "$ENV" = "staging" ]; then
  NAMESPACE="candy-services-staging"
  RELEASE_SUFFIX="-stg"
else
  NAMESPACE="candy-services"
  RELEASE_SUFFIX=""
fi

CLOUD_VALUES="environments/cloud/${CLOUD}.yaml"
if [ ! -f "$CLOUD_VALUES" ]; then
  echo "Unknown cloud '$CLOUD' (expected gke|eks): $CLOUD_VALUES not found" >&2
  exit 1
fi

echo "==> Deploying all services (env: $ENV, cloud: $CLOUD, namespace: $NAMESPACE)..."

for svc in icore euro-virtuals tpay 01-tech; do
  RELEASE="${svc}${RELEASE_SUFFIX}"
  echo ""
  echo "==> $RELEASE"
  # Charts depend on the candy-common library chart — must be vendored first.
  helm dependency build "charts/$svc" >/dev/null
  helm upgrade --install "$RELEASE" "charts/$svc/" \
    --namespace "$NAMESPACE" \
    --create-namespace \
    -f "charts/$svc/values.yaml" \
    -f "$CLOUD_VALUES" \
    -f "charts/$svc/values-${ENV}.yaml" \
    --atomic \
    --timeout=10m \
    --wait
done

echo ""
echo "==> Pods:"
kubectl get pods -n "$NAMESPACE"

echo ""
echo "==> ExternalSecrets:"
kubectl get externalsecret -n "$NAMESPACE" 2>/dev/null || echo "  (none — ESO may be disabled for this cloud/env)"

echo ""
echo "==> Ingress routes:"
kubectl get ingress -n "$NAMESPACE"

#!/usr/bin/env bash
# One-time local bootstrap for CandyPlay on Kind.
#   ./k8s/scripts/local/bootstrap-local.sh && tilt up
set -euo pipefail

CLUSTER=candyplay-local
NAMESPACE=candy-services
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

echo "==> Checking required tools"
for tool in kind kubectl helm tilt docker; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "MISSING: $tool"
    case "$tool" in
      tilt) echo "  install: brew install tilt-dev/tap/tilt" ;;
      kind) echo "  install: brew install kind" ;;
      *)    echo "  install: brew install $tool" ;;
    esac
    exit 1
  fi
done

echo "==> Creating Kind cluster '$CLUSTER' (if absent)"
if ! kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  kind create cluster --config k8s/local/kind-config.yaml
else
  echo "    cluster already exists"
fi

kubectl config use-context "kind-$CLUSTER"

echo "==> Ensuring namespace '$NAMESPACE'"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "==> Vendoring candy-common library chart into each service chart"
for c in icore euro-virtuals tpay 01-tech; do
  helm dependency update "k8s/charts/$c" >/dev/null
done

echo
echo "Bootstrap complete. The Tiltfile lives at the repo root — run from there:"
echo "    cd \"$ROOT\" && tilt up"
echo "(Running 'tilt up' from any other dir makes Tilt create an empty starter Tiltfile -> 'No resources found'.)"
echo "Services will be on  icore :8001  euro-virtuals :8002  tpay :8003  01-tech :8004"

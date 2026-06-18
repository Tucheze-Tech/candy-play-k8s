#!/usr/bin/env bash
# One-command rollback for a CandyPlay service.
#
#   ./k8s/scripts/rollback.sh <service> <env> [revision]
#     service : icore | euro-virtuals | tpay | 01-tech
#     env     : production | staging
#     revision: helm revision to roll back to (default: previous)
#
# Examples:
#   ./k8s/scripts/rollback.sh icore staging          # -> previous revision
#   ./k8s/scripts/rollback.sh tpay production 7       # -> explicit revision 7
#
# NOTE: this rolls back APPLICATION CODE/CONFIG only. DB migrations are
# forward-only — a rollback does NOT revert schema changes. If the bad release
# included a destructive migration, restore from DB backup separately.
set -euo pipefail

SERVICE="${1:-}"
ENVNAME="${2:-}"
REVISION="${3:-}"

if [ -z "$SERVICE" ] || [ -z "$ENVNAME" ]; then
  echo "usage: $0 <service> <production|staging> [revision]" >&2
  exit 1
fi

case "$ENVNAME" in
  production) NS=candy-services;         RELEASE="$SERVICE" ;;
  staging)    NS=candy-services-staging; RELEASE="${SERVICE}-stg" ;;
  *) echo "env must be 'production' or 'staging'" >&2; exit 1 ;;
esac

echo "==> Release history for '$RELEASE' (ns: $NS):"
helm history "$RELEASE" -n "$NS" --max 10

if [ -z "$REVISION" ]; then
  echo "==> Rolling back '$RELEASE' to the PREVIOUS revision"
  helm rollback "$RELEASE" 0 -n "$NS" --wait --timeout 10m
else
  echo "==> Rolling back '$RELEASE' to revision $REVISION"
  helm rollback "$RELEASE" "$REVISION" -n "$NS" --wait --timeout 10m
fi

echo "==> Post-rollback rollout status:"
kubectl rollout status "deploy/${RELEASE}-${SERVICE}" -n "$NS" --timeout=120s
echo "==> Now running image:"
kubectl get deploy "${RELEASE}-${SERVICE}" -n "$NS" \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'

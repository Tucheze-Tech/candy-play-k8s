#!/usr/bin/env bash
# SKELETON — EKS equivalent of gcp/03-create-secrets.sh.
# Service secrets live in AWS Secrets Manager as FLAT JSON (same shape and same
# names as the GCP secrets), consumed via ESO -> envFrom: secretRef.
set -euo pipefail

echo "AWS Secrets Manager seeding is a skeleton — see k8s/docs/gke-to-eks.md." >&2
exit 1

# --- reference ---
# for name in gonga_prd_settings ev_prd_settings tpay_settings 01tech_prd_settings; do
#   aws secretsmanager create-secret --name "$name" \
#     --secret-string file://"/tmp/${name}.json"   # flat {"KEY":"value",...}
# done
# # Same flat-JSON requirement as GKE — see README "Secret format".

#!/usr/bin/env bash
# SKELETON — EKS equivalent of gcp/04-workload-identity.sh.
# IRSA (IAM Roles for Service Accounts) is the AWS arm of the SA identity seam.
# Each service KSA is annotated with eks.amazonaws.com/role-arn (set by
# environments/cloud/eks.yaml + --set serviceAccount.gcpServiceAccount=<arn>).
set -euo pipefail

echo "IRSA setup is a skeleton — see k8s/docs/gke-to-eks.md." >&2
exit 1

# --- reference ---
# CLUSTER=candyplay-prod; REGION=eu-west-1
# for svc in icore ev tpay 01tech external-secrets metabase; do
#   eksctl create iamserviceaccount \
#     --cluster "$CLUSTER" --region "$REGION" \
#     --namespace candy-services --name "${svc}-ksa" \
#     --attach-policy-arn arn:aws:iam::<ACCOUNT>:policy/${svc}-secrets-rds \
#     --approve
# done
# # ESO role goes in namespace external-secrets; wire it into
# # infrastructure/external-secrets/clustersecretstore-aws.yaml.

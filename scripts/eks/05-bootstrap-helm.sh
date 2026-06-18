#!/usr/bin/env bash
# SKELETON — EKS equivalent of gcp/05-bootstrap-helm.sh.
# The platform components are IDENTICAL Helm releases (cert-manager, ESO, Kong,
# Redis, monitoring, Metabase) from the same infrastructure/ values. Only the
# cloud-specific bits differ: storageClass gp3, ESO annotated for IRSA, the AWS
# ClusterSecretStore, and Kong service annotated for an AWS NLB.
set -euo pipefail

echo "EKS platform bootstrap is a skeleton — see k8s/docs/gke-to-eks.md." >&2
exit 1

# --- reference deltas vs gcp/05-bootstrap-helm.sh ---
# 1. ESO service account annotated for IRSA, not Workload Identity:
#      --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="arn:aws:iam::<ACCOUNT>:role/external-secrets-irsa"
# 2. Apply the AWS secret store instead of the GCP one:
#      kubectl apply -f infrastructure/external-secrets/clustersecretstore-aws.yaml
# 3. PVCs use gp3 (set via the eks cloud overlay / infra values override).
# 4. Kong proxy Service gets AWS LB controller NLB annotations instead of the
#    GCP load-balancer-type annotation.
# Everything else (helm repo adds, component versions, wait conditions) is the
# same as the GCP script — copy it and apply the 4 deltas above.

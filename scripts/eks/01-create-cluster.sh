#!/usr/bin/env bash
# SKELETON — EKS equivalent of gcp/01-create-cluster.sh. Not wired (no AWS
# provisioning in scope). Mirrors the GKE Autopilot step using EKS Auto Mode
# (managed Karpenter = per-pod scaling, spot via karpenter.sh/capacity-type).
#
# Prefer the Terraform module: infrastructure/terraform/modules/eks (also a
# skeleton). This script documents the eksctl path as an alternative.
set -euo pipefail

echo "EKS cluster creation is a skeleton — see k8s/docs/gke-to-eks.md before use." >&2
exit 1

# --- reference (uncomment + fill when standing up a real cluster) ---
# CLUSTER=candyplay-prod
# REGION=eu-west-1
# eksctl create cluster \
#   --name "$CLUSTER" --region "$REGION" \
#   --enable-auto-mode \           # EKS Auto Mode (Karpenter)
#   --with-oidc                    # OIDC provider for IRSA (SA identity seam)
#
# # Namespaces (same as GKE):
# for ns in candy-services candy-services-staging kong monitoring metabase \
#           cert-manager external-secrets; do
#   kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
# done
# kubectl label namespace candy-services monitoring=true --overwrite
# kubectl label namespace kong monitoring=true --overwrite

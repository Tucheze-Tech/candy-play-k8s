# EKS cluster — SKELETON. Not applied (no AWS provisioning in scope).
# Mirrors the GKE module's interface so envs/ tfvars are interchangeable.
#
# Recommended real implementation: terraform-aws-modules/eks/aws with
# EKS Auto Mode (Karpenter under the hood) for the Autopilot-equivalent
# experience — per-pod scaling, spot via karpenter.sh/capacity-type, no node
# group management. IRSA is the AWS arm of the ServiceAccount identity seam.
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# ---------------------------------------------------------------------------
# SKELETON ONLY — uncomment + fill when standing up a real EKS cluster.
# ---------------------------------------------------------------------------
# module "eks" {
#   source  = "terraform-aws-modules/eks/aws"
#   version = "~> 20.0"
#
#   cluster_name    = var.cluster_name
#   cluster_version = "1.30"
#
#   # EKS Auto Mode = managed Karpenter (GKE Autopilot equivalent).
#   cluster_compute_config = {
#     enabled    = true
#     node_pools = var.node_spot ? ["general-purpose"] : ["general-purpose"]
#   }
#
#   enable_irsa = var.enable_oidc   # AWS arm of the SA identity seam
# }

output "cluster_name" {
  value = var.cluster_name
}

output "note" {
  value = "EKS module is a skeleton. See k8s/docs/gke-to-eks.md before applying."
}

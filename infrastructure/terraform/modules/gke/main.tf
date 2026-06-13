# GKE Autopilot cluster. Autopilot bills per-pod resource request (no node
# management), and scales system components automatically — the cheap, low-ops
# default for CandyPlay. Workload Identity is the GCP arm of the SA seam.
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_container_cluster" "autopilot" {
  name             = var.cluster_name
  location         = var.region
  enable_autopilot = true

  # Workload Identity pool is implicit on Autopilot, but kept explicit here so
  # the eks module's IRSA equivalent maps 1:1.
  dynamic "workload_identity_config" {
    for_each = var.enable_oidc ? [1] : []
    content {
      workload_pool = "${var.project_id}.svc.id.goog"
    }
  }

  # Autopilot manages spot via pod nodeSelector (cloud.google.com/gke-spot),
  # which the charts set through .Values.cloud.spot — nothing to do at cluster level.
}

output "cluster_name" {
  value = google_container_cluster.autopilot.name
}

output "endpoint" {
  value = google_container_cluster.autopilot.endpoint
}

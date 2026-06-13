module "cluster" {
  source       = "../../modules/gke"
  cluster_name = "candyplay-prod"
  region       = "europe-west3"
  project_id   = var.project_id
  node_spot    = true
  enable_oidc  = true
}

variable "project_id" {
  type    = string
  default = "cm-services-prod"
}

output "cluster_name" {
  value = module.cluster.cluster_name
}

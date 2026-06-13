# Same interface as modules/gke/variables.tf (project_id unused on AWS).
variable "cluster_name" {
  type    = string
  default = "candyplay-prod"
}

variable "region" {
  type    = string
  default = "eu-west-1"
}

variable "project_id" {
  type    = string
  default = "" # unused on AWS; kept for interface parity
}

variable "node_spot" {
  type    = bool
  default = true
}

variable "enable_oidc" {
  description = "Enable IRSA OIDC provider"
  type        = bool
  default     = true
}

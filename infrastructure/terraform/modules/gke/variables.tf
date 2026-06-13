variable "cluster_name" {
  type    = string
  default = "candyplay-prod"
}

variable "region" {
  type    = string
  default = "europe-west3"
}

variable "project_id" {
  type = string
}

variable "node_spot" {
  type    = bool
  default = true
}

variable "enable_oidc" {
  description = "Enable Workload Identity"
  type        = bool
  default     = true
}

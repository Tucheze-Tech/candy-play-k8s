# CandyPlay cluster Terraform

Two cloud modules behind **one shared variable interface** so the cluster can
be stood up on GCP or AWS from the same `tfvars` shape. The Helm charts
(`k8s/charts/*`) are cloud-agnostic and layer on top via `environments/cloud/<cloud>.yaml`.

```
terraform/
  modules/
    gke/    # GKE Autopilot cluster + Workload Identity   (reference impl)
    eks/    # EKS cluster + Karpenter + IRSA              (SKELETON — not applied)
  envs/
    gke-prod/   # real: terraform init/plan/apply targets the live GKE
    eks-prod/   # skeleton: terraform.tfvars.example only, do NOT apply yet
```

## Shared variable interface (both modules accept the same names)

| variable        | meaning                                  |
|-----------------|------------------------------------------|
| `cluster_name`  | cluster name                             |
| `region`        | cloud region                             |
| `project_id`    | GCP project (gke) / unused on eks        |
| `node_spot`     | use spot/preemptible for stateless pods  |
| `enable_oidc`   | enable WI (gke) / IRSA OIDC provider (eks)|

## Status

- **gke-prod**: reference for the existing `candyplay-prod` cluster (the live
  cluster was created via `scripts/01-create-cluster.sh`; this codifies it).
- **eks-prod**: skeleton only. Provisioning AWS is explicitly out of scope —
  see `../../docs/gke-to-eks.md` for the full cutover checklist.

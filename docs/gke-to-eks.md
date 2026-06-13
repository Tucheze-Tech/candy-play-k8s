# GKE → EKS cutover checklist

The CandyPlay platform is built so the **Helm charts never change** between
clouds. All cloud-specific behaviour lives in `environments/cloud/<cloud>.yaml`
(consumed via `.Values.cloud.*`) and in the Terraform module you pick. Moving to
AWS is a finite list of swaps, not a rewrite.

## What is already portable (zero change)

- All 4 service charts + the `candy-common` library chart
- Kong ingress, cert-manager, Prometheus/Grafana/Loki, Metabase
- HPA, NetworkPolicy, migration Jobs
- The unified `envFrom` secret consumption pattern

## The swaps

| Concern | GKE (today) | EKS (target) | Where it changes |
|---|---|---|---|
| Cluster | Autopilot | EKS Auto Mode (Karpenter) | `terraform/modules/{gke,eks}` |
| Workload identity | Workload Identity (GSA) | IRSA (role ARN) | `environments/cloud/eks.yaml` sets `serviceAccount.annotationKey`; pass role ARN via `--set serviceAccount.gcpServiceAccount=<arn>` |
| Secrets backend | GCP Secret Manager | AWS Secrets Manager | `infrastructure/external-secrets/clustersecretstore-aws.yaml`; overlay sets `cloud.secretStore.name=aws-secret-store` |
| Database | Cloud SQL + cloud-sql-proxy sidecar | RDS (direct, via DATABASE_URL in the service secret) | overlay sets `cloudSqlProxy.enabled=false`, `cloud.db.mode=direct` |
| Spot | `cloud.google.com/gke-spot` nodeSelector | `karpenter.sh/capacity-type: spot` | `environments/cloud/eks.yaml` `cloud.spot.nodeSelector` |
| Storage class | `standard-rwo` | `gp3` | overlay `storageClass` (PVCs in infrastructure/) |
| Load balancer | GCLB (`cloud.google.com/load-balancer-type`) | NLB (AWS LB controller annotations) | Kong service annotations |
| Image registry | Artifact Registry | ECR | per-service CI `image.repository` |
| CI cluster auth | `google-github-actions/auth` + WIF | `aws-actions/configure-aws-credentials` + `aws eks update-kubeconfig` | the `eks` branch in `deploy-service.yml` |

## Cutover steps (high level)

1. `terraform apply` the `eks-prod` env (fill the skeleton module first).
2. Install platform components (Kong, ESO, cert-manager, monitoring) on EKS via
   the same `infrastructure/` Helm values (storageClass overridden to `gp3`).
3. Create IRSA roles for each service + ESO; apply `clustersecretstore-aws.yaml`.
4. Replicate service secrets into AWS Secrets Manager as **flat JSON** (same key
   names as GCP).
5. Stand up RDS; put its `DATABASE_URL` into each service's AWS secret.
6. Deploy services: `deploy-service.yml` with `cloud: eks` (renders IRSA
   annotation, drops the cloud-sql-proxy sidecar, targets `aws-secret-store`).
7. DNS cutover once health checks pass on EKS.

## Verify before cutover

```sh
# Both clouds must render valid manifests off the same chart:
helm template icore charts/icore -f charts/icore/values.yaml \
  -f environments/cloud/eks.yaml -f charts/icore/values-production.yaml | kubeconform -summary -ignore-missing-schemas
```
This exact check runs in CI (`pr-validate.yml` → `portability-render`) on every PR.

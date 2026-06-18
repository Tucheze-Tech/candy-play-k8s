# Scripts

Grouped by deployment target. Run all from the `k8s/` repo root unless noted.

```
scripts/
  gcp/      GCP / GKE provisioning + platform bootstrap (the live setup today)
  eks/      AWS / EKS equivalents — SKELETONS, mirror gcp/, not yet wired
  common/   cloud-agnostic (work on whatever kubectl context is active)
  local/    Kind local dev bootstrap
```

## gcp/ (numbered = run in order)

| Script | Does |
|--------|------|
| `01-create-cluster.sh` | GKE Autopilot cluster + namespaces + Workload Identity pool |
| `02-create-cloudsql.sh` | Cloud SQL Postgres + per-service DBs/users |
| `03-create-secrets.sh` | Redis secret + GCP Secret Manager entries |
| `04-workload-identity.sh` | GCP SAs + IAM + KSA↔GSA bindings |
| `05-bootstrap-helm.sh` | cert-manager, ESO, Kong, Redis, Prometheus/Grafana/Loki, Metabase |
| `07-bootstrap-staging.sh` | staging namespace, DBs, secrets, plugins (run after 05) |

Then deploy apps with `common/deploy-services.sh production gke`.

## eks/ (skeletons)

`01-create-cluster.sh` (EKS Auto Mode), `02-create-rds.sh`, `03-create-secrets.sh`
(AWS Secrets Manager), `04-irsa.sh`, `05-bootstrap-helm.sh`. Each mirrors its GCP
counterpart and currently `exit 1`s with a pointer to `docs/gke-to-eks.md`. The
platform bootstrap is the *same* Helm releases as GCP with 4 deltas (gp3 storage,
IRSA-annotated ESO, AWS ClusterSecretStore, NLB Kong annotations).

## common/

| Script | Usage |
|--------|-------|
| `deploy-services.sh` | `deploy-services.sh [production\|staging] [gke\|eks]` — vendors candy-common, `helm upgrade --atomic` all 4 charts with the right cloud overlay |
| `rollback.sh` | `rollback.sh <service> <production\|staging> [revision]` — wraps `helm rollback` |

## local/

`bootstrap-local.sh` — creates the Kind cluster and vendors the candy-common
library chart, then tells you to run `tilt up`. Its data manifests
(`kind-config.yaml`, `dependencies.yaml`) live in `k8s/local/`.

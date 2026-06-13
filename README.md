# candy-play K8s Infrastructure

GKE Autopilot + Kong API Gateway + Helm charts for all candy-play services.

## Architecture

```
api.candyplay.com → GCP LB → Kong Ingress Controller
  /icore/*   → icore (Django 5.2 + FastAPI)
  /ev/*      → euro-virtuals (FastAPI)
  /tpay/*    → tpay (Django 4.2)
  /01tech/*  → 01-tech (Go/chi)
  /grafana/* → Grafana
  /metabase/*→ Metabase BI
```

**Diagram:** [shareable Excalidraw](https://excalidraw.com/#json=reynMWwUgs9v8fDbH6R9_,A0G3ciXgooZdAIoOAkuY_Q) · source at `docs/architecture.excalidraw` (open at excalidraw.com → Hamburger → Open).

## Portability model (GKE ↔ EKS)

The 4 service charts contain **no templates of their own** — they delegate to the
`candy-common` library chart (`charts/candy-common`). All cloud-specific behaviour
is isolated in a `cloud:` values block, overridden per cloud by one file:

```
charts/<svc>/values.yaml          # base (cloud defaults = GKE)
environments/cloud/gke.yaml       # GKE: Workload Identity, Cloud SQL proxy, gke-spot, GCP Secret Mgr
environments/cloud/eks.yaml       # EKS: IRSA, RDS direct, karpenter spot, AWS Secrets Mgr (skeleton)
charts/<svc>/values-local.yaml    # Kind: no proxy/ESO, in-cluster Postgres+Redis
charts/<svc>/values-{staging,production}.yaml
```

Deploy = `helm upgrade <svc> charts/<svc> -f values.yaml -f environments/cloud/<cloud>.yaml -f values-<env>.yaml --set image.tag=<sha>`.
Moving to AWS is a finite swap list, not a rewrite — see `docs/gke-to-eks.md`.
CI (`pr-validate.yml` → `portability-render`) renders **both** clouds on every PR so EKS support can't rot.

## Setup Order

```bash
# 0. GCP prerequisites
./scripts/gcp/01-create-cluster.sh
./scripts/gcp/02-create-cloudsql.sh
./scripts/gcp/03-create-secrets.sh     # update GCP secrets manually after this
./scripts/gcp/04-workload-identity.sh

# 1. Infrastructure
./scripts/gcp/05-bootstrap-helm.sh     # cert-manager, ESO, Kong, Redis, Grafana, Metabase

# 2. App services (cloud-agnostic deploy)
./scripts/common/deploy-services.sh production gke
```

### Scripts layout

Scripts are grouped by target:

| Group | Path | Contents |
|-------|------|----------|
| GCP | `scripts/gcp/` | `01-05` + `07` — cluster, Cloud SQL, secrets, Workload Identity, platform bootstrap, staging |
| EKS | `scripts/eks/` | `01-05` skeletons (cluster, RDS, AWS secrets, IRSA, bootstrap) — mirror GCP, not yet wired |
| Common | `scripts/common/` | `deploy-services.sh` (any cloud), `rollback.sh` |
| Local | `scripts/local/` | `bootstrap-local.sh` (Kind); data manifests in `local/` |

See `scripts/README.md` for details.

## Local development (Tilt + Kind)

No more manual `docker build` + `kind load` + `imagePullPolicy: Never` traps:

```bash
./k8s/scripts/local/bootstrap-local.sh    # create Kind cluster + vendor candy-common
tilt up                           # build, load, deploy all 4 services, live-reload
```

Services: `icore :8001`, `euro-virtuals :8002`, `tpay :8003`, `01-tech :8004`.
Local Postgres (4 DBs) + Redis run in-cluster (`k8s/local/dependencies.yaml`) — the
`values-local.yaml` files point at them, so local never touches a prod database.
Django migrations are a manual trigger in the Tilt UI (`<svc>-migrate`).
Requires `tilt` (`brew install tilt-dev/tap/tilt`).

## Deploy & rollback

- **Deploy**: each service repo calls the reusable `.github/workflows/deploy-service.yml`
  with `service`, `environment`, `cloud`, `image_tag` (the git SHA). It runs
  `helm upgrade --install --atomic --wait`, then a `/health` smoke check.
- **Rollback** (3 layers):
  1. `--atomic` auto-rolls-back any failed rollout.
  2. `./scripts/rollback.sh <service> <production|staging> [revision]` wraps `helm rollback`.
  3. Images are SHA-tagged (never `latest`) → redeploy a previous SHA to roll forward/back.
- **Migrations are forward-only**: rollback reverts app code/config, **not** DB schema.

## Secret format (cutover required)

The unified ESO pattern (`envFrom: secretRef`) needs each upstream secret to be
**flat JSON** `{"KEY":"value",...}`. `ev_prd_settings` / `01tech_prd_settings` already
are. **`gonga_prd_settings` and `tpay_settings` must be converted** from their old
single-`.env`-string form before cutover, e.g.:

```bash
# build JSON from a .env file, then add a new secret version
python3 - <<'PY' > /tmp/s.json
import json,sys
print(json.dumps(dict(l.split("=",1) for l in open("Icore/src/.env") if "=" in l and not l.startswith("#"))))
PY
gcloud secrets versions add gonga_prd_settings --data-file=/tmp/s.json
```

## Estimated Cost

~$175–230/month (europe-west3). See plan for full breakdown.

## Key Design

| Concern | Solution |
|---------|----------|
| API routing | Kong KIC, DB-less mode, `key-auth` plugin per route |
| Secrets | External Secrets Operator → GCP Secret Manager via Workload Identity |
| Database | Single Cloud SQL `candyplay-prod-pg`, one DB per service, Cloud SQL Auth Proxy sidecar |
| TLS | cert-manager + Let's Encrypt, single `candyplay-tls` secret |
| Auth | Kong `key-auth` (X-API-KEY header) + rate-limiting + ip-restriction for callbacks |
| Monitoring | kube-prometheus-stack (Spot pods) |
| Cost | GKE Autopilot (pay/pod), Spot for monitoring/metabase, single LB |

## GCP Secrets Expected

| Secret Name | Used By |
|------------|---------|
| `gonga_prd_settings` | icore (existing, update DATABASE_URL) |
| `ev_prd_settings` | euro-virtuals (new, JSON format) |
| `tpay_settings` | tpay (existing, update DATABASE_URL) |
| `01tech_prd_settings` | 01-tech (new, JSON format) |
| `candyplay_shared_redis` | redis pod credentials |

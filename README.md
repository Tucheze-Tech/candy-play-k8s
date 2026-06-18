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

See `architecture.excalidraw` — open at https://excalidraw.com → Hamburger → Open → select file.

## Setup Order

```bash
# 0. GCP prerequisites
./scripts/01-create-cluster.sh
./scripts/02-create-cloudsql.sh
./scripts/03-create-secrets.sh     # update GCP secrets manually after this
./scripts/04-workload-identity.sh

# 1. Infrastructure
./scripts/05-bootstrap-helm.sh     # cert-manager, ESO, Kong, Redis, Grafana, Metabase

# 2. App services
./scripts/06-deploy-services.sh production
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

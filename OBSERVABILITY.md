# Kong + Grafana/Prometheus — How It All Works

## 1. Kong Ingress Controller — Full Picture

### What Kong IS in this setup

Kong runs as a Deployment inside the `kong` namespace. It has two parts:
- **Kong proxy** — the actual reverse proxy that receives all HTTP traffic (port 443). This is what gets the GCP LoadBalancer IP.
- **Kong Ingress Controller (KIC)** — a controller that watches Kubernetes `Ingress`, `KongPlugin`, and `KongConsumer` objects and translates them into Kong's internal routing config. No database needed — DB-less mode means all config lives as K8s CRDs.

### Request lifecycle — exactly what happens

```
Client sends:
  POST https://api.candyplay.com/icore/api/v1/wallet/changebalance/credit/
  Headers: X-API-KEY: nb99RkQfFXA08ZjHOyUqyNDd

1. GCP LoadBalancer (static IP)
   → TLS terminated here (candyplay-tls cert from cert-manager)
   → forwards plain HTTP to Kong pod

2. Kong proxy receives request
   → Matches route: host=api.candyplay.com, path prefix=/icore
   → Runs plugins IN ORDER:
      a. key-auth plugin
         - reads X-API-KEY header
         - looks up nb99RkQfFXA08ZjHOyUqyNDd against KongConsumer credentials
         - if not found → returns 401 immediately, request dies here
         - if found → attaches consumer identity to request context
      b. rate-limiting plugin
         - checks consumer's request count in last 60s
         - if > 120 → returns 429, request dies here
         - otherwise increments counter (stored in Kong pod memory, policy: local)
      c. prometheus plugin
         - increments Kong's internal metrics counters (latency, status codes, per-route)
         - non-blocking, happens on every request
   → strip-path=true: removes /icore prefix → request becomes /api/v1/wallet/changebalance/credit/
   → forwards to icore Service (ClusterIP) on port 8080

3. icore pod receives
   POST /api/v1/wallet/changebalance/credit/
   Headers: X-API-KEY: <hidden by hide_credentials: true>
   → Django processes normally
```

### Why strip-path matters

Without `konghq.com/strip-path: "true"`, icore would receive:
```
POST /icore/api/v1/wallet/changebalance/credit/
```
And Django would 404 because its URL patterns don't have `/icore/` prefix.
With strip-path, Kong peels off `/icore` before forwarding, so Django receives:
```
POST /api/v1/wallet/changebalance/credit/
```
which matches Django's existing URL conf exactly. **No code changes needed in the services.**

### Internal service-to-service (01-tech → icore)

01-tech calls icore at `http://icore.candy-services.svc.cluster.local:8080/api/v1/...` directly.
This traffic **never touches Kong**. It goes through Kubernetes internal DNS.
The NetworkPolicy on the icore pods allows ingress from the `candy-services` namespace, so this works.
icore's own `X-API-KEY` middleware validates the key at the application level.

### KongConsumer — what it is

A KongConsumer is how Kong knows which API key belongs to which caller:

```yaml
apiVersion: configuration.konghq.com/v1
kind: KongConsumer
metadata:
  name: icore-internal
username: icore-internal
credentials:
  - icore-apikey-credential   # this is a K8s Secret with the actual key value
```

You create one KongConsumer per service that calls the API. For example:
- `tpay-consumer` → key = tpay's ICORE_API_KEY env var value
- `01tech-consumer` → key = 01-tech's ICORE_API_KEY env var value
- `external-api-consumer` → key for external clients

Rate limiting is per-consumer. So tpay getting throttled doesn't affect 01-tech.

### Where to add a new route

1. Add a new `Ingress` in the service's Helm chart `templates/ingress.yaml`
2. Add `KongPlugin` objects in `templates/kongplugin.yaml`
3. `helm upgrade` — KIC picks up the new CRDs within seconds, no Kong restart needed

---

## 2. Prometheus — What It Scrapes and How

### The scraping flow

```
Prometheus (ns: monitoring)
  every 30s, scrapes:
  ├─ Pod annotations (prometheus.io/scrape=true)
  │   ├─ icore pods      → :8080/metrics
  │   ├─ euro-virtuals   → :8080/metrics
  │   ├─ tpay            → :8080/metrics
  │   ├─ 01-tech         → :8080/metrics
  │   └─ Kong pods       → :8100/metrics (Kong's built-in prom endpoint)
  └─ kube-state-metrics  → deployment replicas, pod restarts, OOM kills, etc.
```

Every pod in `charts/*/templates/deployment.yaml` has these annotations:
```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"
  prometheus.io/path: "/metrics"
```

Prometheus sees these annotations and auto-scrapes. If your service doesn't expose `/metrics`, Prometheus gets a connection error — it won't crash, just shows a scrape failure in the Prometheus UI. You can add prometheus-client (Python) or a sidecar exporter if the app doesn't have native metrics.

### Kong prometheus plugin metrics

When `plugin: prometheus` is applied to a route, Kong exposes these counters at `:8100/metrics`:
```
kong_http_requests_total{service,route,method,code,consumer}
kong_request_latency_ms_bucket{...}
kong_upstream_latency_ms_bucket{...}
kong_bandwidth_bytes_total{...}
```

These give you per-route, per-consumer, per-status-code breakdowns. Very useful for seeing which consumer is hammering an endpoint or which route has high latency.

---

## 3. Grafana — Dashboards and Log Access

### How Grafana connects to Prometheus

Grafana is deployed in the same `monitoring` namespace. It has a built-in datasource configured by the `kube-prometheus-stack` Helm chart — it auto-connects to Prometheus at `http://monitoring-kube-prometheus-prometheus:9090` (ClusterIP service). No manual wiring needed.

Access: `https://api.candyplay.com/grafana` (routed via Kong, key-auth protected)

### Useful dashboards to import

| Dashboard | Grafana ID | What it shows |
|-----------|-----------|---------------|
| Kong | 7424 | Requests/s, latency p99, error rates per route |
| Kubernetes Pods | 6781 | CPU/memory per pod, restarts |
| Django | 9528 | Request rate, latency if django-prometheus installed |

Import: Grafana → + → Import → enter ID.

---

## 4. Logs — This Is the Gap You Noticed

**Prometheus does NOT collect logs.** Prometheus only collects numeric metrics. Logs are a separate concern.

### What you have right now (without extra setup)

```
kubectl logs -n candy-services <pod-name> -f          # tail one pod
kubectl logs -n candy-services -l app.kubernetes.io/name=icore --all-containers  # all icore pods
```

This works but is manual. You can't search across pods, and old logs disappear when a pod restarts.

### How to get logs into Grafana (Loki — recommended)

Add Grafana Loki to the monitoring stack. It's lightweight and integrates with Grafana natively (same UI, no extra login).

**Add to `infrastructure/monitoring/values.yaml`:**
```yaml
# Add this section to kube-prometheus-stack values
grafana:
  additionalDataSources:
    - name: Loki
      type: loki
      url: http://loki:3100
      access: proxy
```

**Install Loki + Promtail:**
```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm upgrade --install loki grafana/loki-stack \
  --namespace monitoring \
  --set promtail.enabled=true \
  --set loki.persistence.enabled=true \
  --set loki.persistence.size=10Gi \
  --set loki.persistence.storageClassName=standard-rwo
```

**What Promtail does:** Promtail is a DaemonSet (one pod per node) that reads stdout/stderr from every container on that node and ships logs to Loki. Since GKE Autopilot manages nodes, Promtail still works — it deploys as a DaemonSet and GKE Autopilot schedules it automatically.

**After install — in Grafana:**
- Go to Explore → select Loki datasource
- Query: `{namespace="candy-services", app_kubernetes_io_name="icore"}` → all icore logs
- Query: `{namespace="candy-services"} |= "ERROR"` → all errors across all services
- Query: `{namespace="candy-services", app_kubernetes_io_name="icore"} | json | level="error"` → structured error logs
- Kong access logs: `{namespace="kong"}` → every request that hit Kong (IP, method, path, status, latency)

**Cost:** Loki + Promtail adds ~200Mi RAM on the monitoring Spot pod. Loki storage on a 10Gi PVC = ~$2/month. Very cheap.

### GCP Cloud Logging (alternative, zero extra setup)

GKE Autopilot automatically ships all pod stdout/stderr to **GCP Cloud Logging** (formerly Stackdriver). You already have this — no extra install.

To query:
1. GCP Console → Logging → Log Explorer
2. Filter: `resource.type="k8s_container" AND resource.labels.namespace_name="candy-services"`
3. Or: `resource.type="k8s_container" AND jsonPayload.severity="ERROR"`

This is free for the first 50GiB/month. After that, $0.01/GiB.

**Recommendation:** Use GCP Cloud Logging for now (zero setup, already working), then add Loki when you want logs directly in Grafana dashboards alongside metrics.

---

## 5. Summary — Who Sees What

| Tool | What it sees | How to access |
|------|-------------|---------------|
| **Kong** | All external API traffic — validates keys, rate limits, routes | Config via `kubectl get kongplugin,kongconsumer,ingress -n candy-services` |
| **Prometheus** | Numeric metrics — request rates, latency, pod CPU/RAM, restarts | `kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090` |
| **Grafana** | Dashboards over Prometheus metrics (+ Loki logs after install) | `https://api.candyplay.com/grafana` |
| **GCP Cloud Logging** | All pod stdout/stderr, automatically collected | GCP Console → Logging |
| **Loki** (add-on) | Searchable logs inside Grafana, no context switching | Install with `helm upgrade --install loki grafana/loki-stack` |

---

## 6. Quick Debug Commands

```bash
# See all requests hitting Kong in real time
kubectl logs -n kong -l app.kubernetes.io/name=kong -f

# See icore app logs
kubectl logs -n candy-services -l app.kubernetes.io/name=icore -f --all-containers

# Check if a route is registered in Kong
kubectl get ingress -n candy-services
kubectl get kongplugin -n candy-services

# Check if ESO synced your secrets
kubectl get externalsecret -n candy-services
kubectl describe externalsecret icore-env-secret -n candy-services

# Check HPA status (is it scaling?)
kubectl get hpa -n candy-services

# See Kong's view of all routes (from inside a Kong pod)
kubectl exec -n kong deploy/kong-kong -- kong config db_export /tmp/cfg.yaml && \
  kubectl exec -n kong deploy/kong-kong -- cat /tmp/cfg.yaml
```

# Kong Admin API — Access and Usage

## How to access

Kong Admin API runs on port 8001 inside the cluster (ClusterIP, not public).

```bash
# Open a tunnel from your laptop to Kong Admin API
kubectl port-forward -n kong svc/kong-kong-admin 8001:8001

# In another terminal — verify it works
curl -s http://localhost:8001 | jq .version
```

Then use Insomnia, Postman, or curl against `http://localhost:8001`.

---

## Key Admin API endpoints

```bash
# List all routes (what Kong is routing)
curl -s http://localhost:8001/routes | jq '.data[].paths'

# List all services (upstream backends)
curl -s http://localhost:8001/services | jq '.data[].name'

# List all plugins (active globally and per-route)
curl -s http://localhost:8001/plugins | jq '.data[] | {name, config}'

# List all consumers (API key holders)
curl -s http://localhost:8001/consumers | jq '.data[].username'

# List credentials for a consumer
curl -s http://localhost:8001/consumers/icore-internal/key-auth | jq .
```

---

## Adjusting rate limits

Rate limiting is configured per KongPlugin CRD in Kubernetes. There are two ways to change it:

### Way 1 — Edit the K8s CRD (recommended, persists across restarts)

```bash
kubectl edit kongplugin icore-rate-limit -n candy-services
```

Change the `config` block:
```yaml
config:
  minute: 200      # was 120 — increase to 200 req/min
  hour: 10000      # was 5000
  policy: local
```

KIC picks up the change within ~5 seconds and syncs to Kong. No restart needed.

### Way 2 — Admin API (immediate, but overwritten by KIC on next sync)

```bash
# Find the plugin ID first
PLUGIN_ID=$(curl -s http://localhost:8001/plugins \
  | jq -r '.data[] | select(.name=="rate-limiting" and (.tags // [] | contains(["icore"]))) | .id')

# Patch the config
curl -s -X PATCH http://localhost:8001/plugins/$PLUGIN_ID \
  --data "config.minute=200" \
  --data "config.hour=10000"
```

Use Way 1 for permanent changes. Way 2 for quick live testing only.

---

## Adjusting auth (key-auth) — add/rotate a consumer API key

### Add new consumer

```yaml
# k8s/infrastructure/kong/consumers.yaml
apiVersion: configuration.konghq.com/v1
kind: KongConsumer
metadata:
  name: my-new-client
  namespace: candy-services
  annotations:
    kubernetes.io/ingress.class: kong
username: my-new-client
credentials:
  - my-new-client-apikey
---
apiVersion: v1
kind: Secret
metadata:
  name: my-new-client-apikey
  namespace: candy-services
  labels:
    konghq.com/credential: key-auth
type: Opaque
stringData:
  key: "your-api-key-value-here"
  kongCredType: key-auth
```

```bash
kubectl apply -f k8s/infrastructure/kong/consumers.yaml
```

### Rotate an existing key

```bash
# Update the Secret (ESO will re-sync if pulling from GCP SM)
kubectl patch secret icore-apikey-credential -n candy-services \
  --type='json' \
  -p='[{"op": "replace", "path": "/stringData/key", "value": "new-key-value"}]'
```

Kong picks up the new key within seconds. Old key is immediately invalid.

### Block a consumer temporarily

```bash
# Via Admin API (immediate)
CONSUMER_ID=$(curl -s http://localhost:8001/consumers/icore-internal | jq -r .id)

# Delete their credential (blocks all requests with their key)
curl -X DELETE http://localhost:8001/consumers/$CONSUMER_ID/key-auth/<credential-id>
```

---

## Adjusting auth plugin settings

### Allow additional header names (e.g. X-App-Key alongside X-API-KEY)

```bash
kubectl edit kongplugin icore-key-auth -n candy-services
```

```yaml
config:
  key_names:
    - X-API-KEY
    - X-App-Key       # add second accepted header name
  hide_credentials: true
```

---

## URL reference

| Service | URL | Notes |
|---------|-----|-------|
| **Grafana** | https://api.candyplay.co.ke/grafana | Default user: `admin`. Password: see bootstrap script output or run `kubectl get secret -n monitoring monitoring-grafana -o jsonpath='{.data.admin-password}' \| base64 -d` |
| **Metabase** | https://api.candyplay.co.ke/metabase | First launch runs setup wizard. Creates admin account. |
| **Kong Admin API** | http://localhost:8001 (after port-forward) | Internal only. See port-forward command above. |
| **Prometheus** | `kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090` → http://localhost:9090 | Use to debug metric queries before putting in Grafana |
| **Loki** | Accessed via Grafana → Explore → select Loki datasource | Not exposed externally |

---

## Common Grafana log queries (after Loki is installed)

```
# All icore errors
{namespace="candy-services", app="icore"} |= "ERROR"

# All Kong access logs (every request)
{namespace="kong"}

# Staging icore logs
{namespace="candy-services-staging", app="icore"}

# All 500 errors across all services
{namespace="candy-services"} |= "500"

# Slow requests (if your app logs request time)
{namespace="candy-services"} | json | duration > 1000
```

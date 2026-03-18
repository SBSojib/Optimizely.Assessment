# Phase 3 — Observability

This is how I wired up `hello-service` for metrics and logs on GKE, using GCP-managed services.

## Architecture overview

| Concern | Approach | GCP service |
|---------|----------|-------------|
| **Metrics** | App exposes `/metrics`; GMP scrapes via `PodMonitoring` | Google Managed Service for Prometheus |
| **Logs** | App writes structured JSON to stdout; GKE agent collects | Cloud Logging |
| **Alerting** | Alert policies + email channel defined in Terraform | Cloud Monitoring |

No self-hosted Prometheus, Grafana, Loki, or Elasticsearch is required.

## Directory contents

| File | Purpose |
|------|---------|
| `README.md` | This document — full observability design and verification guide |
| `log-query-examples.md` | Ready-to-use Cloud Logging queries for troubleshooting |

---

## Metrics

### How metrics are exposed

The app uses [`prometheus-net`](https://github.com/prometheus-net/prometheus-net) to expose a `/metrics` endpoint on the same port as the application (8080).

A custom counter is registered:

```
hello_service_http_requests_total{method, endpoint, status_code}
```

This counter increments on every request to business endpoints (`/hello`, etc.) and excludes internal paths (`/health`, `/metrics`) to avoid noise.

Standard process-level metrics (CPU, memory, GC) are also exported automatically by `prometheus-net`.

### How metrics are scraped

The Helm chart deploys a **PodMonitoring** custom resource (`monitoring.googleapis.com/v1`), which is the GMP-native way to configure scraping in GKE. The cluster itself enables Managed Service for Prometheus in Terraform, so metric collection is provisioned declaratively rather than assumed to exist out of band.

```yaml
# Created by helm/hello-service/templates/podmonitoring.yaml
apiVersion: monitoring.googleapis.com/v1
kind: PodMonitoring
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: hello-service
  endpoints:
    - port: http
      interval: 30s
      path: /metrics
```

GMP's managed collectors (running in `gmp-system` namespace) discover this resource and begin scraping automatically. No sidecar or additional operator is needed.

The Helm chart is the single source of truth for PodMonitoring configuration. Scraping is toggled via `metrics.enabled` in `helm/hello-service/values.yaml.example` (or an equivalent values override file).

---

## Alerting

Alerting is implemented as a Terraform module (`terraform/modules/alerting/`) and creates Cloud Monitoring alert policies plus an email notification channel. The policies are scoped to the hello-service namespace and cluster.

| Alert | Condition | Purpose |
| ----- | --------- | ------- |
| **Container Restart Rate** | Restarts > 3 in 10 min | CrashLoopBackOff, OOMKilled, failing health probes |
| **Memory Utilization High** | Container memory > 85% of limit for 5 min | Leading indicator before OOMKill |
| **Service Availability** | No running containers (uptime) for 5 min | Detects loss of available application instances |
| **Error Log Rate** | Error logs (severity ≥ ERROR) > 5 in 5 min | Application exceptions, dependency failures |

**Setup:** Configure `alert_notification_email` in `terraform/environments/dev/alerting.auto.tfvars`, then run `terraform apply` in `terraform/environments/dev`. After apply, verify the email channel in **Monitoring > Alerting > Edit notification channels** so notifications are delivered.

### Verify metrics are available

1. **Port-forward and curl locally:**

```bash
kubectl port-forward svc/hello-service -n hello-app 8080:80
curl http://localhost:8080/metrics | grep hello_service_http_requests_total
```

2. **Query in GCP Console (Cloud Monitoring > Metrics Explorer):**

   - Go to **Monitoring > Metrics Explorer**
   - Select resource type: **Prometheus Target**
   - Metric: `prometheus.googleapis.com/hello_service_http_requests_total/counter`
   - Filter by namespace: `hello-app`

3. **List metric descriptors via Cloud Monitoring API:**

   The `gcloud monitoring` CLI has no `metrics list` subcommand. Use the REST API instead:

```bash
# Get an access token, then list Prometheus metric descriptors
TOKEN=$(gcloud auth print-access-token)
curl -s -H "Authorization: Bearer ${TOKEN}" \
  "https://monitoring.googleapis.com/v3/projects/YOUR_PROJECT_ID/metricDescriptors?filter=metric.type%3Dstarts_with(\"prometheus.googleapis.com/hello_service\")"
```

---

## Logs

### How logs are emitted

The `/hello` handler writes a flat JSON log line to stdout using `Console.WriteLine`:

```json
{
  "severity": "INFO",
  "message": "hello_request_handled",
  "trace_id": "TRACE_ID",
  "status_code": 200,
  "method": "GET",
  "path": "/hello",
  "pod_name": "hello-service-xxxxx-xxxxx",
  "timestamp_utc": "TIMESTAMP_UTC"
}
```

**Why flat JSON to stdout?**
GKE's built-in Fluent Bit agent parses JSON lines from container stdout into Cloud Logging `jsonPayload` fields. Writing flat JSON (instead of nested ILogger output) makes every field directly queryable without path traversal. The `severity` field is recognised by Cloud Logging to set the log entry severity level. This is the GCP-recommended pattern for structured logging.

Framework logs (startup, errors) are also JSON-formatted via ASP.NET Core's `AddJsonConsole()`.

### How to verify logs are queryable

**GCP Console — Logs Explorer:**

Navigate to **Logging > Logs Explorer** and run:

```
resource.type="k8s_container"
resource.labels.namespace_name="hello-app"
resource.labels.container_name="hello-service"
jsonPayload.message="hello_request_handled"
```

---

## Debrief walkthrough

### 1. Generate traffic

```bash
kubectl port-forward svc/hello-service -n hello-app 8080:80 &

# Single request
curl -H "Authorization: Bearer YOUR_API_KEY_VALUE" http://localhost:8080/hello

# Burst of 20 requests
for i in $(seq 1 20); do curl -s -H "Authorization: Bearer YOUR_API_KEY_VALUE" http://localhost:8080/hello; done
```

### 2. Grab a trace_id

```bash
curl -s -H "Authorization: Bearer YOUR_API_KEY_VALUE" http://localhost:8080/hello | jq -r '.traceId'
```

Example output: `TRACE_ID`

### 3. Filter logs by trace_id

**Logs Explorer query:**

```
resource.type="k8s_container"
resource.labels.namespace_name="hello-app"
jsonPayload.trace_id="TRACE_ID"
```

**gcloud CLI:**

```bash
gcloud logging read \
  'resource.type="k8s_container" AND resource.labels.namespace_name="hello-app" AND jsonPayload.trace_id="TRACE_ID"' \
  --project=YOUR_PROJECT_ID \
  --limit=5 \
  --format=json
```

### 4. Verify metrics scraping

**Confirm PodMonitoring is deployed:**

```bash
kubectl get podmonitoring -n hello-app
```

**Check metric in Cloud Monitoring:**

1. Open **Monitoring > Metrics Explorer**
2. Resource type: **Prometheus Target**
3. Metric: `prometheus.googleapis.com/hello_service_http_requests_total/counter`
4. Group by: `endpoint` to see per-path breakdown

---

## Files changed in Phase 3

| File | Change |
|------|--------|
| `app/Program.cs` | Added metrics counter, structured JSON log, `/metrics` endpoint |
| `app/HelloService.csproj` | Added `prometheus-net.AspNetCore` 8.2.1 |
| `helm/hello-service/values.yaml.example` | Added `metrics` configuration block |
| `helm/hello-service/templates/deployment.yaml` | Added Prometheus pod annotations plus pod HA and security hardening |
| `helm/hello-service/templates/podmonitoring.yaml` | **New** — GMP PodMonitoring resource |
| `helm/hello-service/templates/pdb.yaml` | **New** — PodDisruptionBudget for safer rollouts and node drains |
| `observability/README.md` | **New** — this document |

## Rebuilding after Phase 3 changes

```bash
cd app

IMAGE=YOUR_REGION-docker.pkg.dev/YOUR_PROJECT_ID/YOUR_REPO_NAME/hello-service
TAG=v1

docker build -t ${IMAGE}:${TAG} .
docker push ${IMAGE}:${TAG}

HELLO_SERVICE_GSA=$(cd ../terraform/environments/dev && terraform output -raw hello_service_gsa_email)

helm upgrade --install hello-service ../helm/hello-service \
  -f ../helm/hello-service/values.yaml.example \
  --set global.projectId=YOUR_PROJECT_ID \
  --set serviceAccount.gcpServiceAccount=${HELLO_SERVICE_GSA} \
  --set image.tag=${TAG} \
  --wait
```

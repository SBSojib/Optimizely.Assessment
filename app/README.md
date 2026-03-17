# Phase 2 — Application Build & Deploy

Minimal HTTP service (`hello-service`) built with ASP.NET Core 8, containerised and deployed to GKE via Helm.

## Prerequisites

| Tool | Purpose |
|------|---------|
| .NET 8 SDK | Local build / debug (optional) |
| Docker | Container image build |
| gcloud CLI | GCP authentication, GKE credentials |
| Helm 3 | Kubernetes deployment |
| kubectl | Cluster interaction |

## 1. Build the Docker image

```bash
cd app

IMAGE=YOUR_REGION-docker.pkg.dev/YOUR_PROJECT_ID/YOUR_REPO_NAME/hello-service
TAG=v1

dotnet build
docker build -t ${IMAGE}:${TAG} .
```

## 2. Authenticate Docker to Artifact Registry

```bash
gcloud auth configure-docker YOUR_REGION-docker.pkg.dev
```

## 3. Push the image

```bash
docker push ${IMAGE}:${TAG}
```

## 4. Get GKE credentials

```bash
gcloud container clusters get-credentials YOUR_CLUSTER_NAME \
  --zone YOUR_ZONE \
  --project YOUR_PROJECT_ID
```

## 5. Deploy with Helm

```bash
HELLO_SERVICE_GSA=$(cd ../terraform/environments/dev && terraform output -raw hello_service_gsa_email)

helm upgrade --install hello-service ../helm/hello-service \
  -f ../helm/hello-service/values.yaml.example \
  --set global.projectId=YOUR_PROJECT_ID \
  --set serviceAccount.create=true \
  --set serviceAccount.name=YOUR_KSA_NAME \
  --set serviceAccount.workloadIdentity.enabled=true \
  --set serviceAccount.gcpServiceAccount=${HELLO_SERVICE_GSA} \
  --set image.tag=${TAG} \
  --wait
```

To use a different namespace or image:

```bash
helm upgrade --install hello-service ../helm/hello-service \
  -f ../helm/hello-service/values.yaml.example \
  --set image.tag=${TAG} \
  --set namespace=hello-app \
  --wait
```

## 6. Verify the deployment

### Check pods are running

```bash
kubectl get pods -n hello-app
kubectl get pdb -n hello-app
```

Expected: two pods in `Running` state with `1/1` ready.

### Port-forward to the service

```bash
kubectl port-forward svc/hello-service -n hello-app 8080:80
```

### Test /health

```bash
curl http://localhost:8080/health
```

Expected response:

```json
{ "status": "ok" }
```

### Test /hello

```bash
curl -H "Authorization: Bearer YOUR_API_KEY_VALUE" http://localhost:8080/hello
# or
curl -H "X-API-Key: YOUR_API_KEY_VALUE" http://localhost:8080/hello
```

Expected response (values will differ):

```json
{
  "message": "Hello from hello-service!",
  "podName": "hello-service-xxxxx-xxxxx",
  "traceId": "TRACE_ID",
  "timestampUtc": "2026-03-13T16:05:00.0000000Z"
}
```

### Test /metrics

```bash
curl http://localhost:8080/metrics
```

Expected: Prometheus text exposition format including `hello_service_http_requests_total`.

## Endpoints

| Path | Method | Description |
|------|--------|-------------|
| `/health` | GET | Liveness / readiness probe — returns `{"status":"ok"}` |
| `/hello` | GET | Returns greeting with pod name, trace ID, and UTC timestamp; requires `Authorization: Bearer <key>` or `X-API-Key` |
| `/metrics` | GET | Prometheus-compatible metrics endpoint |

## Design notes

- **High availability**: 2 replicas by default, required pod anti-affinity across nodes, topology spread constraints, and a `PodDisruptionBudget` with `minAvailable: 1`.
- **Probes**: readiness and liveness probes hit `/health`.
- **Pod name injection**: Kubernetes Downward API sets `POD_NAME` env var from `metadata.name`.
- **Workload Identity**: The workload must use a dedicated Kubernetes service account. Keep `serviceAccount.name` aligned with the `hello_service_service_account` Terraform input so the Workload Identity binding matches the deployed pod identity.
- **Non-root container**: Dockerfile uses the built-in `$APP_UID` user from the .NET 8 base image.
- **Pod hardening**: The deployment enforces `runAsNonRoot`, runtime-default seccomp, dropped Linux capabilities, disallows privilege escalation, and mounts the root filesystem read-only.
- **Image size**: multi-stage build keeps the final image small (aspnet runtime only).
- **Metrics** (Phase 3): `prometheus-net` exposes a `/metrics` endpoint with a per-endpoint request counter (`hello_service_http_requests_total`).
- **Structured logging** (Phase 3): `/hello` emits a flat JSON log line to stdout with `trace_id`, `status_code`, `method`, `path`, `pod_name`, and `timestamp_utc`. Cloud Logging ingests this as `jsonPayload`.

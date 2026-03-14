# Cloud Logging Query Examples

Quick-reference queries for the debrief and day-to-day troubleshooting.

## All hello-service logs

```
resource.type="k8s_container"
resource.labels.namespace_name="hello-app"
resource.labels.container_name="hello-service"
```

## Filter by trace_id

```
resource.type="k8s_container"
resource.labels.namespace_name="hello-app"
jsonPayload.trace_id="<YOUR_TRACE_ID>"
```

## Only /hello handler logs

```
resource.type="k8s_container"
resource.labels.namespace_name="hello-app"
jsonPayload.message="hello_request_handled"
```

## Errors only

```
resource.type="k8s_container"
resource.labels.namespace_name="hello-app"
resource.labels.container_name="hello-service"
severity>=ERROR
```

## gcloud CLI — filter by trace_id

```bash
gcloud logging read \
  'resource.type="k8s_container" AND resource.labels.namespace_name="hello-app" AND jsonPayload.trace_id="<YOUR_TRACE_ID>"' \
  --project=YOUR_PROJECT_ID \
  --limit=5 --format=json
```

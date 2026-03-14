# Optimizely DevOps Take-Home Assessment

Infrastructure-as-code, containerised application deployment, and observability pipeline for a reference microservice running on GKE.

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────┐
│  GCP Project: YOUR_PROJECT_ID                                    │
│                                                                  │
│  ┌─────────────── VPC (YOUR_VPC_NAME) ─────────────────────────┐ │
│  │                                                             │ │
│  │  Subnet 10.20.0.0/20    ┌──────────────────────────────┐    │ │
│  │  Pods   10.24.0.0/14    │  GKE Cluster (zonal)         │    │ │
│  │  Svcs   10.28.0.0/20    │  ┌────────┐  ┌────────┐      │    │ │
│  │                          │  │ Node 1 │  │ Node 2 │      │    │ │
│  │                          │  │  pod-a  │  │  pod-b  │      │    │ │
│  │                          │  └────────┘  └────────┘      │    │ │
│  │                          │  e2-standard-2 · private IP  │    │ │
│  │                          │  Workload Identity enabled   │    │ │
│  │                          └──────────────────────────────┘    │ │
│  │                                                             │ │
│  │  Cloud Router ──► Cloud NAT (outbound internet only)        │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  Artifact Registry (Docker)    GCS Bucket (Terraform state)      │
│  Cloud Logging (pod logs)      GMP (Prometheus metrics)          │
│  └──────────────────────────────────────────────────────────────────┘
```

## Repository Structure

```
├── terraform/
│   ├── bootstrap/              # Step 1 — creates Terraform state bucket
│   ├── environments/dev/       # Step 2 — root module wiring all modules
│   └── modules/
│       ├── networking/         # VPC, subnet, Cloud Router, Cloud NAT
│       ├── gke/                # GKE cluster, node pool, IAM
│       └── supporting_infra/   # Artifact Registry
├── app/                        # ASP.NET Core 8 HTTP service + Dockerfile
├── helm/hello-service/         # Helm chart for GKE deployment
└── observability/              # Observability stack config + documentation
```

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| Terraform | >= 1.6 | Infrastructure provisioning |
| gcloud CLI | latest | GCP authentication, cluster credentials |
| Docker | latest | Container image build |
| Helm | >= 3.x | Kubernetes deployment |
| kubectl | latest | Cluster interaction |

## End-to-End Setup

### Step 0 — Authenticate and Configure GCP

```bash
gcloud auth login
gcloud auth application-default login

gcloud config set project YOUR_PROJECT_ID
gcloud config set auth/impersonate_service_account \
  YOUR_SERVICE_ACCOUNT_EMAIL

export GOOGLE_IMPERSONATE_SERVICE_ACCOUNT=YOUR_SERVICE_ACCOUNT_EMAIL
```

### Step 1 — Bootstrap Terraform State Bucket

The GCS backend bucket must exist before Terraform can use it. The bootstrap module creates it with local state.

```bash
cd terraform/bootstrap

terraform init
terraform plan \
  -var="project_id=YOUR_PROJECT_ID" \
  -var="terraform_state_bucket_name=YOUR_BUCKET_NAME"

terraform apply \
  -var="project_id=YOUR_PROJECT_ID" \
  -var="terraform_state_bucket_name=YOUR_BUCKET_NAME"
```

### Step 2 — Provision Infrastructure

```bash
cd terraform/environments/dev

cp common.auto.tfvars.example common.auto.tfvars
cp networking.auto.tfvars.example networking.auto.tfvars
cp gke.auto.tfvars.example gke.auto.tfvars
cp apps.auto.tfvars.example apps.auto.tfvars
cp backend.hcl.example backend.hcl

terraform init -backend-config=backend.hcl
terraform plan
terraform apply

HELLO_SERVICE_GSA=$(terraform output -raw hello_service_gsa_email)
```

This creates the VPC, subnet, Cloud NAT, GKE cluster (private nodes, Workload Identity, and Managed Prometheus), Artifact Registry, workload identity bindings for the application, and the required project APIs.

### Step 3 — Build and Push the Container Image

```bash
cd app

IMAGE=YOUR_REGION-docker.pkg.dev/YOUR_PROJECT_ID/YOUR_REPO_NAME/hello-service
TAG=v1

gcloud auth configure-docker YOUR_REGION-docker.pkg.dev

docker build -t ${IMAGE}:${TAG} .
docker push ${IMAGE}:${TAG}
```

### Step 4 — Connect to the Cluster

```bash
gcloud container clusters get-credentials YOUR_CLUSTER_NAME \
  --zone YOUR_ZONE \
  --project YOUR_PROJECT_ID
```

### Step 5 — Deploy with Helm

```bash
helm upgrade --install hello-service helm/hello-service \
  --set global.projectId=YOUR_PROJECT_ID \
  --set serviceAccount.gcpServiceAccount=${HELLO_SERVICE_GSA} \
  --set image.tag=${TAG} \
  --wait
```

### Step 6 — Verify the Deployment

```bash
# Check pods are running (expect 2 pods, 1/1 Ready, on separate nodes)
kubectl get pods -n hello-app -o wide

# Verify the PodDisruptionBudget is protecting at least one replica
kubectl get pdb -n hello-app

# Port-forward to the service
kubectl port-forward svc/hello-service -n hello-app 8080:80
```

Test the endpoints:

```bash
# Health check
curl http://localhost:8080/health
# → {"status":"ok"}

# Hello endpoint (returns pod name, trace ID, timestamp)
curl http://localhost:8080/hello
# → {"message":"Hello from hello-service!","podName":"hello-service-...","traceId":"...","timestampUtc":"..."}

# Prometheus metrics
curl http://localhost:8080/metrics | grep hello_service_http_requests_total
```

### Step 7 — Verify Observability

**Metrics (GMP):**

```bash
# Confirm PodMonitoring is deployed
kubectl get podmonitoring -n hello-app
```

In GCP Console: Monitoring -> Metrics Explorer -> Resource type "Prometheus Target" -> Metric `prometheus.googleapis.com/hello_service_http_requests_total/counter`.

**Logs (Cloud Logging):**

```bash
# Get a trace_id from a request
TRACE_ID=$(curl -s http://localhost:8080/hello | python3 -c "import sys,json; print(json.load(sys.stdin)['traceId'])")

# Query Cloud Logging for that trace_id
gcloud logging read \
  "resource.type=\"k8s_container\" AND resource.labels.namespace_name=\"hello-app\" AND jsonPayload.trace_id=\"${TRACE_ID}\"" \
  --project=YOUR_PROJECT_ID \
  --limit=5 --format=json
```

Or in Logs Explorer:

```
resource.type="k8s_container"
resource.labels.namespace_name="hello-app"
jsonPayload.trace_id="<YOUR_TRACE_ID>"
```

## Architecture Decisions

### 1. GCP Managed Prometheus (GMP) + Cloud Logging over Self-Hosted Stacks

**Choice:** Use GMP PodMonitoring for metrics scraping and Cloud Logging for log ingestion instead of deploying Prometheus Operator, Grafana, Loki, or ELK.

**Why:** For a two-replica reference service, deploying and maintaining a self-hosted observability stack adds significant operational overhead (storage, retention policies, HA for the monitoring stack itself) without proportional benefit. GMP is zero-infrastructure — the managed collectors run in `gmp-system` and scrape PodMonitoring targets automatically. Cloud Logging is always-on for GKE. Both integrate directly with Cloud Monitoring dashboards and alerting. This is the approach most GKE-native platform teams adopt as their baseline.

**Trade-off:** Less portability to non-GCP environments. If the team later needs multi-cloud observability, a self-hosted stack (e.g., Prometheus + Thanos + Grafana) would be more appropriate.

### 2. Zonal GKE Cluster Instead of Regional

**Choice:** Deploy a zonal cluster (`asia-south2-a`) rather than a regional cluster.

**Why:** A regional cluster replicates the control plane across three zones and can run nodes in multiple zones, but the control-plane replication alone triples the management fee from $0.00/hr (zonal Standard) to ~$0.10/hr. For a development/assessment environment with a 24-hour budget constraint, zonal is the pragmatic choice. The module design allows straightforward promotion to regional by changing the `location` parameter from a zone to a region.

**Trade-off:** Single zone of failure for both the control plane and nodes. Not suitable for production workloads requiring high availability at the infrastructure level.

### 3. Custom Node Service Account with Least Privilege

**Choice:** Create a dedicated GCP service account for GKE nodes instead of using the default Compute Engine service account.

**Why:** The default Compute Engine SA has the `Editor` role on the project, which violates least privilege and dramatically increases blast radius if a node is compromised. The custom SA is granted only the five roles it needs: `logging.logWriter`, `monitoring.metricWriter`, `monitoring.viewer`, `stackdriver.resourceMetadata.writer`, and `artifactregistry.reader`. This is a security baseline that any production cluster should have.

**Trade-off:** Slightly more Terraform code and IAM management. If future workloads need additional permissions, roles must be explicitly added.

### 4. Cloud NAT for Private Node Egress

**Choice:** Private GKE nodes (no public IP) with Cloud NAT for internet-bound traffic.

**Why:** Removing public IPs from nodes eliminates direct inbound internet attack surface. Cloud NAT provides managed, scalable outbound connectivity for pulling images, OS patches, and external API calls. Combined with Private IP Google Access on the subnet, nodes can reach Google APIs without traversing the public internet.

**Trade-off:** Cloud NAT has per-GB egress processing costs (~$0.045/GB). For this assessment workload the cost is negligible.

### 5. Helm over Plain Manifests or Kustomize

**Choice:** Package the Kubernetes deployment as a Helm chart rather than raw manifests or Kustomize overlays.

**Why:** Helm provides templating, release management, `helm upgrade --install` idempotency, and a clear values-driven configuration surface. It is the most widely adopted packaging format for Kubernetes in production, making it immediately familiar to platform teams. Kustomize would also work but lacks release tracking and rollback capabilities.

**Trade-off:** Helm adds a client-side dependency and its template syntax can become complex. For a single-service chart this complexity is minimal.

## Estimated GCP Cost (24 Hours)

| Resource | Spec | Rate | 24 hr Cost |
|----------|------|------|------------|
| GKE management fee (zonal Standard) | 1 cluster | $0.00/hr | **$0.00** |
| Compute Engine (nodes) | 2 × e2-standard-2 (2 vCPU, 8 GB) | ~$0.067/hr each | **$3.22** |
| Boot disks | 2 × 50 GB pd-standard | ~$0.04/GB/mo | **$0.13** |
| Cloud NAT | gateway + minimal egress | ~$0.045/hr + per-GB | **$1.10** |
| Artifact Registry | < 1 GB stored | ~$0.10/GB/mo | **< $0.01** |
| Cloud Logging | < 1 GiB ingested (free tier) | first 50 GiB free | **$0.00** |
| Cloud Monitoring (GMP) | included with GKE | included | **$0.00** |
| GCS (state bucket) | < 1 MB | negligible | **< $0.01** |
| **Total** | | | **~$4.50** |

> Actual costs may vary slightly by region and real-time pricing. The `asia-south2` region was chosen for proximity; `us-central1` would be ~10% cheaper.

## Cleanup

```bash
# Remove Helm release
helm uninstall hello-service

# Destroy infrastructure
cd terraform/environments/dev
terraform destroy

# Destroy state bucket (optional)
cd terraform/bootstrap
terraform destroy \
  -var="project_id=YOUR_PROJECT_ID" \
  -var="terraform_state_bucket_name=YOUR_BUCKET_NAME"
```

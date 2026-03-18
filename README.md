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
│       ├── github_oidc/        # GitHub Actions Workload Identity Federation
│       ├── secrets/            # Secret Manager shells + IAM
│       ├── alerting/           # Cloud Monitoring policies + notification channel
│       └── supporting_infra/   # Artifact Registry
├── app/                        # ASP.NET Core 8 HTTP service + Dockerfile
├── helm/hello-service/         # Helm chart for GKE deployment
├── observability/              # Observability stack config + documentation
├── docs/                       # Supporting design notes
├── tests/                      # Integration tests for the app
└── .github/workflows/          # CI, CD, and Terraform drift detection
```

## Prerequisites


| Tool       | Version | Purpose                                 |
| ---------- | ------- | --------------------------------------- |
| Terraform  | >= 1.6  | Infrastructure provisioning             |
| gcloud CLI | latest  | GCP authentication, cluster credentials |
| Docker     | latest  | Container image build                   |
| Helm       | >= 3.x  | Kubernetes deployment                   |
| kubectl    | latest  | Cluster interaction                     |


## CI/CD

GitHub Actions handles both continuous integration and continuous deployment. No long-lived GCP service account keys are stored in GitHub — all GCP authentication is done via [Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation).

### Flow


| Trigger                              | Workflow                 | What it does                                                                                                                                    |
| ------------------------------------ | ------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| Pull request touching `terraform/**` | `terraform-validate.yml` | Check Terraform formatting and run `terraform init -backend=false` + `terraform validate` for the bootstrap and `dev` root modules              |
| Pull request → `master`              | `ci.yml`                 | Build and test the .NET app; build the Docker image (no push); lint and render the Helm chart using `values.yaml.example`                       |
| Push to `master`                     | `deploy.yml`             | Build and push the image to Artifact Registry (tagged with `$GITHUB_SHA`); deploy to GKE via Helm; run `/health` and `/hello` auth smoke checks |
| Schedule / manual dispatch           | `terraform-drift.yml`    | Run read-only `terraform plan -detailed-exitcode` against the remote state backend to detect out-of-band changes                                |


```
PR opened / updated
  └── CI: dotnet build + test → docker build (no push) → helm lint
                 ↓ all checks pass
PR merged to master
  └── CD: docker build + push (SHA tag) → helm upgrade --install → smoke test
```

### Authentication

The CD workflow uses `google-github-actions/auth` with a WIF provider and service account email. GitHub exchanges a short-lived OIDC token for a GCP access token — no JSON key file is ever created or stored.

### GitHub Environment: `dev`

The CD workflow targets the GitHub Environment named `**dev**`. Variables and secrets must be configured there.

**Variables** (`vars.`*)


| Name                     | Example value                                                                                                    |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------- |
| `GCP_PROJECT_ID`         | `skynet-2026-code-test-sojib`                                                                                    |
| `GCP_REGION`             | `asia-south2`                                                                                                    |
| `GKE_CLUSTER`            | `opti-devops-gke`                                                                                                |
| `GKE_LOCATION`           | `asia-south2-a`                                                                                                  |
| `ARTIFACT_REGISTRY_REPO` | `asia-south2-docker.pkg.dev/…/hello-service`                                                                     |
| `K8S_NAMESPACE`          | `hello-app`                                                                                                      |
| `HELM_RELEASE`           | `hello-service`                                                                                                  |
| `HELLO_SERVICE_KSA_NAME` | Kubernetes service account name used by the deployment (must match `hello_service_service_account` in Terraform) |


**Secrets** (`secrets.`*)


| Name                         | Description                                                                                                                                                  |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `WORKLOAD_IDENTITY_PROVIDER` | Full WIF provider resource name                                                                                                                              |
| `GCP_SERVICE_ACCOUNT`        | GSA email that GitHub Actions impersonates for GCP operations                                                                                                |
| `HELLO_SERVICE_GSA_EMAIL`    | Runtime GSA email annotated onto the Kubernetes `ServiceAccount`                                                                                             |
| `HELLO_SERVICE_API_KEY`      | API key for `/hello` — same value as stored in Secret Manager for `hello-svc-api-key`. Used by the CD smoke test to verify authenticated /hello returns 200. |


### Drift Detection Setup

The scheduled drift workflow reuses the same GitHub Environment (`dev`) and requires a few additional settings.

**Variables** (`vars.`*)


| Name              | Description                                                    |
| ----------------- | -------------------------------------------------------------- |
| `TF_STATE_BUCKET` | GCS bucket that stores Terraform remote state                  |
| `TF_STATE_PREFIX` | Object prefix used by the `terraform/environments/dev` backend |


**Secrets** (`secrets.`*)


| Name                        | Description                                                                                                                       |
| --------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| `DRIFT_GCP_SERVICE_ACCOUNT` | Read-only drift-detection service account email from Terraform output                                                             |
| `TF_VARS`                   | Combined HCL content of the `common`, `networking`, `gke`, `apps`, `secrets`, `github_oidc`, and `alerting` `*.auto.tfvars` files |


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

Copy `terraform.tfvars.example` to a real `terraform.tfvars`, fill in your actual values there, and do not commit that file. The real `*.tfvars` files are intentionally gitignored.

**Note on tfvars loading:** Terraform automatically loads `terraform.tfvars` and any `*.auto.tfvars` files from the current working directory. If you create `terraform/bootstrap/terraform.tfvars`, you can run `terraform plan` / `terraform apply` without `-var=...`. The explicit `-var` flags below are an alternative for one-off runs.

```bash
cd terraform/bootstrap
terraform init
terraform plan
terraform apply 
```

### Step 2 — Provision Infrastructure

```bash
cd terraform/environments/dev

cp common.auto.tfvars.example common.auto.tfvars
cp networking.auto.tfvars.example networking.auto.tfvars
cp gke.auto.tfvars.example gke.auto.tfvars
cp apps.auto.tfvars.example apps.auto.tfvars
cp secrets.auto.tfvars.example secrets.auto.tfvars
cp github_oidc.auto.tfvars.example github_oidc.auto.tfvars
cp alerting.auto.tfvars.example alerting.auto.tfvars
cp backend.hcl.example backend.hcl

terraform init -backend-config=backend.hcl
terraform plan
terraform apply

HELLO_SERVICE_GSA=$(terraform output -raw hello_service_gsa_email)
```

Populate the copied `*.auto.tfvars` files locally with your actual values. Keep the committed `*.example` files placeholder-only and keep the real `*.tfvars` files out of git.

This creates the VPC, subnet, Cloud NAT, GKE cluster (private nodes, Workload Identity, and Managed Prometheus), Artifact Registry, workload identity bindings for the application, Secret Manager secret shells, and the required project APIs.

### Step 3 — Populate Secrets (Manual, Outside Git)

Terraform creates the secret **shells** in Secret Manager. You must populate the actual values manually. This keeps secret values out of Terraform state and git.

```bash
# Add a secret version (repeat for each secret in secrets.auto.tfvars)
printf "your-actual-api-key-value" | \
  gcloud secrets versions add hello-svc-api-key \
    --project=YOUR_PROJECT_ID \
    --data-file=-
```

The hello-service reads these secrets at startup via the GCP Secret Manager SDK, authenticated automatically through Workload Identity. No JSON keys or Kubernetes Secrets are involved. See [docs/secrets-management.md](docs/secrets-management.md) for the full design.

**Note:** Once secrets are populated, the **CI/CD deploy path** (merge to `master` via PR after CI and Terraform validation pass) will roll out new pods that load the secret at startup and protect `/hello` with that API key.

### Step 4 — Deploy the Application via CI/CD

Deployment is done only through CI/CD. Before the first deploy, create the GitHub Environment **`dev`** (Settings → Environments → New environment) and add the following **variables** and **secrets**. All of them are used by the workflows that target `dev` (CD and optional drift detection).

**Variables** (Settings → Environments → `dev` → Environment variables):


| Name                     | Used by | Description                                                                                           |
| ------------------------ | ------- | ----------------------------------------------------------------------------------------------------- |
| `GCP_PROJECT_ID`         | Deploy  | GCP project ID                                                                                        |
| `GCP_REGION`             | Deploy  | Region (e.g. `asia-south2`)                                                                           |
| `GKE_CLUSTER`            | Deploy  | GKE cluster name                                                                                      |
| `GKE_LOCATION`           | Deploy  | Cluster location — zone (e.g. `asia-south2-a`) or region                                              |
| `ARTIFACT_REGISTRY_REPO` | Deploy  | Full image repo path (e.g. `asia-south2-docker.pkg.dev/PROJECT_ID/REPO_NAME/hello-service`)           |
| `K8S_NAMESPACE`          | Deploy  | Kubernetes namespace (e.g. `hello-app`)                                                               |
| `HELM_RELEASE`           | Deploy  | Helm release name (e.g. `hello-service`)                                                              |
| `HELLO_SERVICE_KSA_NAME` | Deploy  | Kubernetes service account name for the app (must match `hello_service_service_account` in Terraform) |
| `TF_STATE_BUCKET`        | Drift   | GCS bucket that stores Terraform remote state                                                         |
| `TF_STATE_PREFIX`        | Drift   | Object prefix for the `terraform/environments/dev` backend (e.g. `env/dev`)                           |


**Secrets** (Settings → Environments → `dev` → Environment secrets):


| Name                         | Used by       | Description                                                                                                                       |
| ---------------------------- | ------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| `WORKLOAD_IDENTITY_PROVIDER` | Deploy, Drift | Full Workload Identity Federation provider resource name (from Terraform / IAM)                                                   |
| `GCP_SERVICE_ACCOUNT`        | Deploy        | GCP service account email that GitHub Actions impersonates for build/deploy                                                       |
| `HELLO_SERVICE_GSA_EMAIL`    | Deploy        | Runtime GSA email annotated on the Kubernetes ServiceAccount (e.g. from `terraform output hello_service_gsa_email`)               |
| `HELLO_SERVICE_API_KEY`      | Deploy        | API key for `/hello` — same value as in Secret Manager (`hello-svc-api-key`). Used by the CD smoke test.                          |
| `DRIFT_GCP_SERVICE_ACCOUNT`  | Drift         | Read-only drift-detection service account email (from Terraform output)                                                           |
| `TF_VARS`                    | Drift         | Combined HCL content of the `common`, `networking`, `gke`, `apps`, `secrets`, `github_oidc`, and `alerting` `*.auto.tfvars` files |


Once the **Deploy** variables and secrets are set, open a **pull request** to `master`. CI (`ci.yml`) and Terraform validation (`terraform-validate.yml`) run on the PR; do not push directly to `master` (it's restricted anyway). After the PR is merged, the `deploy.yml` workflow runs: it builds + pushes the image (tagged with `$GITHUB_SHA`), deploys via Helm, and runs authenticated smoke tests. Add the **Drift** entries if you use the scheduled Terraform drift workflow. Full reference: [GitHub Environment: `dev`](#github-environment-dev).

### Step 5 — Verify the Deployment

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
# Health check (always open — used by probes and smoke test)
curl http://localhost:8080/health
# → {"status":"ok"}

# Hello endpoint — always requires an API key.
# In-cluster, it is typically loaded from Secret Manager; locally, you can also set API_KEY directly.
# Send the key via Authorization header or X-API-Key header (use the value you stored in Secret Manager).
curl -H "Authorization: Bearer YOUR_API_KEY_VALUE" http://localhost:8080/hello
# or
curl -H "X-API-Key: YOUR_API_KEY_VALUE" http://localhost:8080/hello
# → {"message":"Hello from hello-service!","podName":"hello-service-...","traceId":"...","timestampUtc":"..."}

# Without the key, you get 401:
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/hello
# → 401

# Prometheus metrics (always open)
curl http://localhost:8080/metrics | grep hello_service_http_requests_total
```

### Step 6 — Verify Observability

All verification below is **CLI-only** (no UI/Console required).

**Logs (Cloud Logging):**

Use the **actual** API key value (the one you stored in Secret Manager for `hello-svc-api-key`). If you use a placeholder or wrong key, `/hello` returns 401 and the response body has no `traceId`, so the one-liner below will fail with `KeyError: 'traceId'`.

**If Cloud Logging returns `[]`:** Logs from GKE can take 1–2 minutes to appear. If the **broad** query below also returns `[]`, then container logs from `hello-app` are not visible in Cloud Logging for your current identity (check GKE logging configuration and IAM: the identity needs permission to read log entries, e.g. `roles/logging.viewer` or `logging.logEntries.list`). You can still verify that the app emits the expected log line using **kubectl** (see fallback below).

```bash
# Optional: confirm recent logs from hello-app are visible in Cloud Logging (no trace filter)
gcloud logging read \
  'resource.type="k8s_container" AND resource.labels.namespace_name="hello-app"' \
  --project=YOUR_PROJECT_ID --limit=5 --freshness=5m --format=json

# Replace YOUR_ACTUAL_API_KEY with the value from Secret Manager (hello-svc-api-key)
TRACE_ID=$(curl -s -H "Authorization: Bearer YOUR_ACTUAL_API_KEY" http://localhost:8080/hello | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('traceId','') or d.get('trace_id','') or sys.exit('No traceId in response (check API key and that /hello returned 200)'))")

# Query Cloud Logging for that trace_id (if you get [], wait 1–2 min and retry; or use kubectl fallback below)
gcloud logging read \
  "resource.type=\"k8s_container\" AND resource.labels.namespace_name=\"hello-app\" AND jsonPayload.trace_id=\"${TRACE_ID}\"" \
  --project=YOUR_PROJECT_ID \
  --limit=5 --format=json
```

**Fallback — verify log line with kubectl (no Cloud Logging required):** After calling `/hello`, confirm the app emitted a log line containing `trace_id`. With multiple replicas, the request is handled by one pod; use that pod’s name from the response so the log line isn’t lost in the aggregated stream. Run these one after the other (or copy the full block):

```bash
HELLO_RESP=$(curl -s -H "X-API-Key: YOUR_ACTUAL_API_KEY" http://localhost:8080/hello)
POD=$(echo "$HELLO_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('podName',''))")
kubectl logs -n hello-app "$POD" --tail=30 | grep -E '"trace_id"|hello_request_handled'
```

**Metrics (GCP Managed Prometheus via Cloud Monitoring API):**

The `gcloud` CLI does not expose a `time-series list` subcommand. Use the Cloud Monitoring REST API with an access token:

```bash
# Replace YOUR_PROJECT_ID. Uses current gcloud credentials.
TOKEN=$(gcloud auth print-access-token)
PROJECT=YOUR_PROJECT_ID
end=$(date -u +%Y-%m-%dT%H:%M:%SZ)
start=$(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ)
curl -s -H "Authorization: Bearer ${TOKEN}" \
  "https://monitoring.googleapis.com/v3/projects/${PROJECT}/timeSeries?filter=metric.type%3D%22prometheus.googleapis.com%2Fhello_service_http_requests_total%2Fcounter%22&interval.startTime=${start}&interval.endTime=${end}&view=FULL&pageSize=10"
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

### 5. GCP Secret Manager SDK over CSI Driver or External Secrets Operator

**Choice:** The application reads secrets directly from Secret Manager at startup using the official SDK, authenticated via Workload Identity. Secret values are never stored in Kubernetes Secrets, Helm values, or git.

**Why:** Both the Secrets Store CSI Driver and External Secrets Operator are excellent for large platforms with many services, but they require installing cluster-wide components (a DaemonSet or an operator with CRDs) that add operational overhead disproportionate to a single-service assessment. The direct SDK approach is Google's recommended pattern for GKE workloads with Workload Identity — it treats Secret Manager as the single source of truth, provides automatic authentication with zero stored credentials, and includes built-in audit logging via Cloud Audit Logs.

**Trade-off:** Each application must include the Secret Manager SDK dependency. In a larger platform with dozens of services, a centralized operator that syncs secrets to Kubernetes would reduce per-service boilerplate at the cost of additional infrastructure.

### 6. Helm over Plain Manifests or Kustomize

**Choice:** Package the Kubernetes deployment as a Helm chart rather than raw manifests or Kustomize overlays.

**Why:** Helm provides templating, release management, `helm upgrade --install` idempotency, and a clear values-driven configuration surface. It is the most widely adopted packaging format for Kubernetes in production, making it immediately familiar to platform teams. Kustomize would also work but lacks release tracking and rollback capabilities.

**Trade-off:** Helm adds a client-side dependency and its template syntax can become complex. For a single-service chart this complexity is minimal.

## Estimated GCP Cost (24 Hours)


| Resource                            | Spec                             | Rate                | 24 hr Cost  |
| ----------------------------------- | -------------------------------- | ------------------- | ----------- |
| GKE management fee (zonal Standard) | 1 cluster                        | $0.00/hr            | **$0.00**   |
| Compute Engine (nodes)              | 2 × e2-standard-2 (2 vCPU, 8 GB) | ~$0.067/hr each     | **$3.22**   |
| Boot disks                          | 2 × 50 GB pd-standard            | ~$0.04/GB/mo        | **$0.13**   |
| Cloud NAT                           | gateway + minimal egress         | ~$0.045/hr + per-GB | **$1.10**   |
| Artifact Registry                   | < 1 GB stored                    | ~$0.10/GB/mo        | **< $0.01** |
| Cloud Logging                       | < 1 GiB ingested (free tier)     | first 50 GiB free   | **$0.00**   |
| Cloud Monitoring (GMP)              | included with GKE                | included            | **$0.00**   |
| GCS (state bucket)                  | < 1 MB                           | negligible          | **< $0.01** |
| **Total**                           |                                  |                     | **~$4.50**  |


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


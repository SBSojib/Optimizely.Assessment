# Optimizely DevOps Take-Home Assessment

Submission for the Optimizely DevOps take-home. Includes Terraform for GCP/GKE, a small ASP.NET Core service (containerized), a Helm chart, and basic observability (metrics + logs).

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

GitHub Actions runs CI/CD. No long-lived GCP keys in GitHub. Auth uses [Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation).

### Flow


| Trigger                              | Workflow                 | What it does                                                                                                                                    |
| ------------------------------------ | ------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| Pull request touching `terraform/**` | `terraform-validate.yml` | Check Terraform formatting and run `terraform init -backend=false` + `terraform validate` for the bootstrap and `dev` root modules              |
| Pull request targeting `master`      | `ci.yml`                 | Build and test the .NET app; build the Docker image (no push); lint and render the Helm chart using `values.yaml.example`                       |
| Push to `master`                     | `deploy.yml`             | Build and push the image to Artifact Registry (tagged with `$GITHUB_SHA`); deploy to GKE via Helm; run `/health` and `/hello` auth smoke checks |
| Schedule / manual dispatch           | `terraform-drift.yml`    | Run read-only `terraform plan -detailed-exitcode` against the remote state backend to detect out-of-band changes                                |


```
PR opened / updated
  └── CI: dotnet build + test, then docker build (no push), then helm lint
                 ↓ all checks pass
PR merged to master
  └── CD: docker build + push (SHA tag), then helm upgrade --install, then smoke test
```

### Authentication

CD uses `google-github-actions/auth` with a WIF provider + service account email. GitHub swaps a short-lived OIDC token for a GCP access token. No JSON key files.

### GitHub Environment: `dev`

Workflows target the GitHub Environment `dev`. Vars/secrets are listed in [Step 4](#step-4--deploy-the-application-via-cicd).


### Drift Detection Setup

The scheduled drift workflow also uses `dev` and needs extra entries.

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

The Terraform backend bucket must exist first. The bootstrap module creates it using local state.

Copy `terraform.tfvars.example` to `terraform.tfvars`, fill it in, and don’t commit it. Real `*.tfvars` are gitignored.

Terraform auto-loads `terraform.tfvars` and `*.auto.tfvars` in the current directory.

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

Fill the copied `*.auto.tfvars` locally with real values. Keep the committed `*.example` files as placeholders. Don’t commit real `*.tfvars`.

This provisions VPC/subnet, Cloud NAT, a private-node GKE cluster (Workload Identity + Managed Prometheus), Artifact Registry, app identity bindings, Secret Manager secret shells, alerting, and required APIs.

### Step 3 — Populate Secrets (Manual, Outside Git)

Terraform creates Secret Manager secret **shells**. You add secret versions yourself. Secret values stay out of git and Terraform state.

```bash
# Add a secret version (repeat for each secret in secrets.auto.tfvars)
printf "your-actual-api-key-value" | \
  gcloud secrets versions add hello-svc-api-key \
    --project=YOUR_PROJECT_ID \
    --data-file=-
```

`hello-service` reads secrets at startup using the Secret Manager SDK via Workload Identity. No JSON keys. No Kubernetes Secrets. See [docs/secrets-management.md](docs/secrets-management.md).

Once secrets exist, merging to `master` deploys and `/hello` is protected by that API key.

### Step 4 — Deploy the Application via CI/CD

Deployment happens via CI/CD only. Create GitHub Environment `dev` and add the vars/secrets below.

**Variables** (Settings > Environments > `dev` > Environment variables):


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


**Secrets** (Settings > Environments > `dev` > Environment secrets):


| Name                         | Used by       | Description                                                                                                                       |
| ---------------------------- | ------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| `WORKLOAD_IDENTITY_PROVIDER` | Deploy, Drift | Full Workload Identity Federation provider resource name (from Terraform / IAM)                                                   |
| `GCP_SERVICE_ACCOUNT`        | Deploy        | GCP service account email that GitHub Actions impersonates for build/deploy                                                       |
| `HELLO_SERVICE_GSA_EMAIL`    | Deploy        | Runtime GSA email annotated on the Kubernetes ServiceAccount (e.g. from `terraform output hello_service_gsa_email`)               |
| `HELLO_SERVICE_API_KEY`      | Deploy        | API key for `/hello` — same value as in Secret Manager (`hello-svc-api-key`). Used by the CD smoke test.                          |
| `DRIFT_GCP_SERVICE_ACCOUNT`  | Drift         | Read-only drift-detection service account email (from Terraform output)                                                           |
| `TF_VARS`                    | Drift         | Combined HCL content of the `common`, `networking`, `gke`, `apps`, `secrets`, `github_oidc`, and `alerting` `*.auto.tfvars` files |


After setting Deploy entries, open a PR to `master`. PR runs `ci.yml` + `terraform-validate.yml`. Merge runs `deploy.yml`: build + push (tag `$GITHUB_SHA`), Helm deploy, then authenticated smoke tests. Add Drift entries only if you enable drift detection.

### Step 5 — Verify the Deployment

```bash
# Expect 2 pods on separate nodes
kubectl get pods -n hello-app -o wide

kubectl get pdb -n hello-app

kubectl port-forward svc/hello-service -n hello-app 8080:80
```

Test the endpoints:

```bash
curl http://localhost:8080/health

curl -H "Authorization: Bearer YOUR_API_KEY_VALUE" http://localhost:8080/hello
curl -H "X-API-Key: YOUR_API_KEY_VALUE" http://localhost:8080/hello

curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/hello

curl http://localhost:8080/metrics | grep hello_service_http_requests_total
```

### Step 6 — Verify Observability

All checks below are CLI-only.

**Logs (Cloud Logging):**

Target state: JSON logs to stdout should land in Cloud Logging as `resource.type="k8s_container"` for namespace `hello-app`.

In my test environment, stdout logs didn’t show up in Cloud Logging (queries kept returning `[]` even after traffic). App worked and logged to stdout. Cluster workload logging was enabled. Node SA had `roles/logging.logWriter` and `cloud-platform` scope. No obvious routing/view config dropping `k8s_container`.

```bash
# Baseline: do we see any recent GKE-related logs at all?
# If this is empty too, it strongly suggests a project/ingestion issue rather than a query filter issue.
gcloud logging read \
  'resource.type=("gce_instance" OR "k8s_node" OR "k8s_container")' \
  --project=YOUR_PROJECT_ID \
  --limit=50 --freshness=30m \
  --format='value(resource.type,logName)'

# Narrow: container logs for the namespace (expected to return entries)
gcloud logging read \
  'resource.type="k8s_container" AND resource.labels.namespace_name="hello-app"' \
  --project=YOUR_PROJECT_ID \
  --limit=20 --freshness=30m \
  --format=json

# Targeted: generate one request, capture its trace_id, then search for it in Cloud Logging.
# (Use the actual API key value stored in Secret Manager for hello-svc-api-key.)
TRACE_ID=$(curl -s -H "Authorization: Bearer YOUR_ACTUAL_API_KEY" http://localhost:8080/hello | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('traceId','') or d.get('trace_id','') or '')")
gcloud logging read \
  "resource.type=\"k8s_container\" AND resource.labels.namespace_name=\"hello-app\" AND (jsonPayload.trace_id=\"${TRACE_ID}\" OR jsonPayload.traceId=\"${TRACE_ID}\")" \
  --project=YOUR_PROJECT_ID \
  --limit=20 --freshness=30m \
  --format=json
```

**Metrics (GCP Managed Prometheus via Cloud Monitoring API):**

`gcloud` doesn’t expose a `time-series list` command. Use the Monitoring REST API with an access token:

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

Required vs chosen.

### Constraints (mandated by the assessment prompt)

- **GKE Standard (not Autopilot)**: Autopilot was explicitly disallowed so node pool configuration could be demonstrated.
- **Private nodes**: Nodes have no public IPs; workloads must not be directly accessible from the internet.
- **Outbound internet reachability from inside the VPC**: Workloads must be able to reach the internet for image pulls and updates while remaining private.
- **Dedicated node pool**: At least 2 nodes, using `e2-standard-2` or smaller, to stay within budget.
- **Workload Identity enabled**: Required on the cluster and node pool.
- **Deliverable format**: Terraform split into at least networking/cluster/supporting modules; sensitive values via variables; required outputs present.
- **Observability outcomes**: service exposes metrics; metrics are scraped/queryable; pod logs are ingested/queryable; `/hello` emits structured JSON with at least `trace_id` and HTTP status; demonstrate filtering by `trace_id`.

### Core architecture choices (areas where the prompt gave options or was silent)

#### 1. Observability baseline: GMP + Cloud Logging

- **Choice**: GMP (`PodMonitoring`) for scraping; Cloud Logging for logs.
- **Why**: Meets “scraped + queryable” with minimal ops overhead.
- **Trade-off**: GCP-specific.

#### 2. Zonal GKE cluster (cost-first)

- **Choice**: Zonal cluster (`asia-south2-a`).
- **Why**: Cheaper; still shows the required patterns.
- **Trade-off**: Single-zone blast radius.

#### 3. Custom node service account

- **Choice**: Dedicated node SA, not the default Compute Engine SA.
- **Why**: Smaller blast radius; explicit permissions.
- **Trade-off**: More IAM surface area.

#### 4. Private nodes + outbound via Cloud NAT

- **Choice**: Cloud Router + Cloud NAT for egress.
- **Why**: Outbound internet without inbound exposure.
- **Trade-off**: NAT cost.

#### 5. Helm packaging

- **Choice**: Helm.
- **Why**: Values-driven config + repeatable deploy/rollback.
- **Trade-off**: Template overhead.

#### 6. Datapath V2 (eBPF)

- **Choice**: `ADVANCED_DATAPATH`.
- **Why**: Modern default; better scaling than big iptables rule sets.
- **Trade-off**: Can break legacy iptables assumptions (not relevant here).

#### 7. Container hardening

- **Choice**: Multi-stage build + non-root runtime.
- **Why**: Smaller image, less attack surface.
- **Trade-off**: Base image choice can impact native deps (not an issue here).

#### 8. HA scheduling

- **Choice**: Hard anti-affinity + topology spread.
- **Why**: Keeps replicas on different nodes.
- **Trade-off**: Needs enough nodes; after node loss a replica can sit Pending until capacity returns.

### Optional / stretch-goal choices (added beyond prompt minimum)

#### 9. Secrets via Secret Manager SDK

- **Choice**: Read secrets from Secret Manager at startup via Workload Identity.
- **Why**: No secret values in git/Helm/K8s Secrets; no operator needed.
- **Trade-off**: Per-service code; operators scale better for many services.

#### 10. GitHub Actions auth via WIF (OIDC)

- **Choice**: WIF with conditions scoped to repo + environment (`dev`).
- **Why**: No long-lived credentials; environment gates deployments.
- **Trade-off**: More setup in GitHub + IAM.

#### 11. Delivery safety

- **Choice**: `helm upgrade --install --atomic` + post-deploy smoke tests.
- **Why**: Catches rollout failures and bad config.
- **Trade-off**: Slower; tests only cover what’s probed.

#### 12. Terraform drift detection (read-only)

- **Choice**: Scheduled `terraform plan` using a read-only identity.
- **Why**: Detects drift without allowing writes.
- **Trade-off**: More config/credentials plumbing.

## Estimated GCP Cost (24 Hours)

Based on [GCP pricing](https://cloud.google.com/pricing) for `asia-south2` (Delhi), March 2026.

| Resource                            | Spec                              | Rate                                         | 24 hr Cost  |
| ----------------------------------- | --------------------------------- | -------------------------------------------- | ----------- |
| GKE management fee (zonal Standard) | 1 cluster                         | $0.10/hr (covered by [$74.40/mo free tier])  | **$0.00**   |
| Compute Engine (nodes)              | 2 × e2-standard-2 (2 vCPU, 8 GB) | [$0.0811/hr each] in asia-south2             | **$3.89**   |
| Boot disks                          | 2 × 50 GB pd-standard             | [$0.048/GB/mo] in asia-south2                | **$0.16**   |
| Cloud NAT                           | gateway (2 VMs, 1 IP) + minimal egress | [$0.0014/VM/hr] + [$0.005/IP/hr] + [$0.045/GiB] | **~$0.19** |
| Artifact Registry                   | < 1 GB stored                     | [$0.10/GB/mo] (first 0.5 GB free)            | **< $0.01** |
| Cloud Logging                       | < 1 GiB ingested (free tier)      | [first 50 GiB/mo free]                       | **$0.00**   |
| Cloud Monitoring (GMP)              | ~2 replicas, low sample rate      | [$0.06/M samples] (first tier); ~$0.00/day at this scale | **~$0.00** |
| GCS (state bucket)                  | < 1 MB                            | [negligible]                                 | **< $0.01** |
| Secret Manager                      | 1 secret, minimal access          | [free tier: 6 versions + 10K ops/mo]         | **$0.00**   |
| **Total**                           |                                   |                                              | **~$4.25 + NAT egress** |

<details>
<summary>Pricing sources</summary>

| Resource | Source |
|---|---|
| GKE management fee & free tier | [GKE Pricing](https://cloud.google.com/kubernetes-engine/pricing) |
| Compute Engine (e2-standard-2) | [VM Instance Pricing](https://cloud.google.com/compute/vm-instance-pricing#e2_sharedcore) — asia-south2 on-demand |
| Persistent Disk (pd-standard) | [Disk Pricing](https://cloud.google.com/compute/disks-image-pricing#disk) |
| Cloud NAT | [Cloud NAT Pricing](https://cloud.google.com/nat/pricing) |
| Artifact Registry | [Artifact Registry Pricing](https://cloud.google.com/artifact-registry/pricing) |
| Cloud Logging | [Cloud Logging Pricing](https://cloud.google.com/logging/pricing) |
| Cloud Monitoring | [Cloud Monitoring Pricing](https://cloud.google.com/monitoring/pricing) |
| Secret Manager | [Secret Manager Pricing](https://cloud.google.com/secret-manager/pricing) |

</details>

Note: `us-central1` is ~20% cheaper for Compute Engine ($0.067/hr vs $0.0811/hr). I used `asia-south2` for proximity.

## Cleanup

```bash
# Remove Helm release
helm uninstall hello-service

# Destroy infrastructure
cd terraform/environments/dev
terraform destroy

# Destroy state bucket (optional)
cd terraform/bootstrap
terraform destroy
```


# Terraform — GCP Infrastructure (Phase 1)

This repository provisions the foundational GCP infrastructure for the Optimizely DevOps assessment.

## Architecture Overview

- **VPC** with a custom subnet and secondary IP ranges for GKE pods and services
- **Cloud Router + Cloud NAT** for private-node egress to the internet
- **GKE Standard cluster** (zonal, private nodes, Workload Identity enabled)
- **Artifact Registry** Docker repository for container images
- **GCS bucket** for Terraform remote state (bootstrapped separately)

## Repository Structure

```text
terraform/
├── bootstrap/                # Step 1: creates the Terraform state bucket
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
├── modules/
│   ├── networking/           # VPC, subnet, Cloud Router, Cloud NAT
│   ├── gke/                  # GKE cluster, node pool, node SA, IAM
│   └── supporting_infra/     # Artifact Registry
├── environments/
│   └── dev/                  # Step 2: root module that orchestrates all modules
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       ├── common.auto.tfvars.example
│       ├── networking.auto.tfvars.example
│       ├── gke.auto.tfvars.example
│       ├── apps.auto.tfvars.example
│       └── backend.hcl.example
└── README.md
```

The two executable root modules are `bootstrap/` and `environments/dev/`.
Reusable logic lives in `modules/`.

## Prerequisites

1. **Terraform** >= 1.6 installed
2. **gcloud CLI** installed
3. **Authentication and Configuration**:
   Run the following commands to authenticate and configure service account impersonation before running any Terraform commands:

```bash
# Login to Google Cloud
gcloud auth login

# Set the project
gcloud config set project YOUR_PROJECT_ID

# Configure service account impersonation
gcloud config set auth/impersonate_service_account YOUR_SERVICE_ACCOUNT_EMAIL

gcloud auth application-default login --impersonate-service-account=YOUR_SERVICE_ACCOUNT_EMAIL

# Verify permissions (optional)
gcloud config list
gcloud compute instances list
```

4. The target project must allow the impersonated service account to enable and use required APIs. The Terraform code enables the necessary project services declaratively as part of the deployment flow.

## Deployment Flow

### Step 1 — Bootstrap the State Bucket

Terraform cannot use a GCS backend bucket that does not yet exist. The bootstrap
module creates it using local state.

```bash
cd terraform/bootstrap

# Copy and customise the example file
cp terraform.tfvars.example terraform.tfvars

terraform init

terraform plan

terraform apply
```

### Step 2 — Deploy Infrastructure

```bash
cd terraform/environments/dev

# Copy and customise the example files
cp common.auto.tfvars.example common.auto.tfvars
cp networking.auto.tfvars.example networking.auto.tfvars
cp gke.auto.tfvars.example gke.auto.tfvars
cp apps.auto.tfvars.example apps.auto.tfvars
cp backend.hcl.example backend.hcl

# Initialise with the GCS backend
terraform init -backend-config=backend.hcl

# Review the execution plan
terraform plan

# Apply
terraform apply

# Capture the Google service account that is pre-bound for hello-service Workload Identity
terraform output -raw hello_service_gsa_email
```

### Connecting to the Cluster

```bash
gcloud container clusters get-credentials YOUR_CLUSTER_NAME \
  --zone YOUR_ZONE \
  --project YOUR_PROJECT_ID
```

## Design Decisions

### Why Cloud NAT?

GKE private nodes have no external IP addresses. Without Cloud NAT they cannot
reach the public internet, which is required for pulling container images from
external registries, downloading OS patches, and communicating with external
APIs. Cloud NAT provides managed, scalable outbound connectivity without
exposing nodes to inbound internet traffic.

### Why Private GKE Nodes?

Private nodes reduce the attack surface by eliminating direct internet
accessibility. Combined with Cloud NAT for egress, this follows the principle of
least exposure: workloads can reach the internet when needed but are never
directly reachable from it. This is a standard security baseline for production
Kubernetes clusters.

### Why Workload Identity?

Workload Identity is the GCP-recommended way for GKE workloads to authenticate
to Google Cloud APIs. It eliminates the need to create and distribute service
account keys, maps Kubernetes service accounts to Google Cloud service accounts,
and provides fine-grained, auditable access control. It is the GKE equivalent of
IAM Roles for Service Accounts (IRSA) on AWS EKS.

### Why a Custom Node Service Account?

The default Compute Engine service account has the Editor role on the project,
which violates the principle of least privilege. A dedicated node service account
with only the required roles (logging, monitoring, Artifact Registry read) limits
blast radius in the event of a node compromise.

### Why a Zonal Cluster?

A zonal cluster is chosen for cost efficiency in a development/assessment
context. The module design allows straightforward promotion to a regional cluster
by changing the `location` parameter from a zone to a region.

## Outputs

After `terraform apply` in `environments/dev/`, the following outputs are
available:

| Output                         | Description                                |
| ------------------------------ | ------------------------------------------ |
| `cluster_endpoint`             | GKE control plane endpoint (sensitive)     |
| `node_pool_name`               | Name of the primary node pool              |
| `artifact_registry_url`        | Docker repository URL in Artifact Registry |
| `cluster_name`                 | Name of the GKE cluster                    |
| `cluster_ca_certificate`       | Cluster CA certificate (sensitive)         |
| `node_service_account_email`   | GKE node service account email             |
| `hello_service_gsa_email`      | GSA bound to the app's Kubernetes SA       |
| `vpc_name`                     | Name of the VPC network                    |
| `subnet_name`                  | Name of the GKE subnet                     |

## Cleanup

```bash
# Destroy infrastructure
cd terraform/environments/dev
terraform destroy

# Destroy state bucket (optional, after infrastructure is destroyed)
cd terraform/bootstrap
terraform destroy
```

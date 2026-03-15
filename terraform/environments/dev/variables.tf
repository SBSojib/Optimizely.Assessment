variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region for resource deployment"
  type        = string
}

variable "zone" {
  description = "GCP zone for zonal resources (e.g., GKE cluster)"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "naming_prefix" {
  description = "Prefix used in resource names for consistent naming"
  type        = string
}

# --- Networking ---

variable "vpc_name" {
  description = "Name of the VPC network"
  type        = string
}

variable "subnet_name" {
  description = "Name of the GKE subnet"
  type        = string
}

variable "subnet_cidr" {
  description = "Primary CIDR range for the GKE subnet"
  type        = string
}

variable "pods_secondary_range_name" {
  description = "Name of the secondary IP range for GKE pods"
  type        = string
}

variable "pods_secondary_cidr" {
  description = "CIDR for the GKE pods secondary range"
  type        = string
}

variable "services_secondary_range_name" {
  description = "Name of the secondary IP range for GKE services"
  type        = string
}

variable "services_secondary_cidr" {
  description = "CIDR for the GKE services secondary range"
  type        = string
}

# --- GKE ---

variable "gke_cluster_name" {
  description = "Name of the GKE cluster"
  type        = string
}

variable "gke_node_pool_name" {
  description = "Name of the primary GKE node pool"
  type        = string
}

variable "gke_machine_type" {
  description = "Machine type for node pool instances"
  type        = string
}

variable "gke_node_count" {
  description = "Number of nodes per zone in the node pool"
  type        = number
}

variable "gke_disk_size_gb" {
  description = "Boot disk size in GB for node pool instances"
  type        = number
}

variable "gke_disk_type" {
  description = "Boot disk type for node pool instances"
  type        = string
}

variable "gke_master_ipv4_cidr_block" {
  description = "CIDR block for the GKE master network (must be /28)"
  type        = string
}

variable "gke_master_authorized_cidr_blocks" {
  description = "CIDRs allowed to reach the GKE control plane public endpoint"
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

variable "hello_service_namespace" {
  description = "Namespace used by the hello-service Helm release"
  type        = string
}

variable "hello_service_service_account" {
  description = "Kubernetes service account name used by hello-service"
  type        = string
}

# --- Supporting Infrastructure ---

variable "artifact_registry_repository_id" {
  description = "ID of the Artifact Registry Docker repository"
  type        = string
}

# --- GitHub OIDC / Workload Identity Federation ---

variable "github_owner" {
  description = "GitHub organisation or user that owns the repository (e.g., SBSojib)"
  type        = string
}

variable "github_repository" {
  description = "GitHub repository name, without the owner prefix (e.g., Optimizely.Assessment)"
  type        = string
}

variable "github_environment" {
  description = "GitHub Actions Environment name whose OIDC tokens are trusted. Must match the 'environment:' key in the workflow job (e.g., dev)."
  type        = string
}

variable "github_oidc_pool_id_suffix" {
  description = "Optional suffix for WIF pool/provider IDs. Set to \"-v2\" (or similar) to work around 409 when the original pool is soft-deleted and undelete fails. Update GitHub Actions secrets from terraform output after apply."
  type        = string
  default     = ""
}

variable "terraform_state_bucket_name" {
  description = "Name of the GCS bucket used for Terraform state (backend). Required for granting the drift-detection SA read access. Must match the bucket in backend.hcl."
  type        = string
}

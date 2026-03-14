terraform {
  required_version = ">= 1.6"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  backend "gcs" {}
}

provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  common_labels = {
    environment = var.environment
    managed_by  = "terraform"
    project     = var.naming_prefix
  }

  required_services = toset([
    "artifactregistry.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com", # SA impersonation via WIF token exchange
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "sts.googleapis.com",            # Security Token Service — required for WIF
  ])
}

resource "google_project_service" "required" {
  for_each = local.required_services

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# ---------------------------------------------------------------------------
# Networking: VPC, subnet, Cloud Router, Cloud NAT
# ---------------------------------------------------------------------------

module "networking" {
  source = "../../modules/networking"

  project_id                    = var.project_id
  region                        = var.region
  vpc_name                      = var.vpc_name
  subnet_name                   = var.subnet_name
  subnet_cidr                   = var.subnet_cidr
  pods_secondary_range_name     = var.pods_secondary_range_name
  pods_secondary_cidr           = var.pods_secondary_cidr
  services_secondary_range_name = var.services_secondary_range_name
  services_secondary_cidr       = var.services_secondary_cidr
  labels                        = local.common_labels
}

# ---------------------------------------------------------------------------
# GKE: cluster, node pool, IAM
# ---------------------------------------------------------------------------

module "gke" {
  source = "../../modules/gke"

  project_id                    = var.project_id
  region                        = var.region
  zone                          = var.zone
  cluster_name                  = var.gke_cluster_name
  network_id                    = module.networking.vpc_id
  subnet_id                     = module.networking.subnet_id
  pods_secondary_range_name     = module.networking.pods_secondary_range_name
  services_secondary_range_name = module.networking.services_secondary_range_name
  node_pool_name                = var.gke_node_pool_name
  naming_prefix                 = var.naming_prefix
  environment                   = var.environment
  hello_service_namespace       = var.hello_service_namespace
  hello_service_service_account = var.hello_service_service_account
  labels                        = local.common_labels

  machine_type                  = var.gke_machine_type
  node_count                    = var.gke_node_count
  disk_size_gb                  = var.gke_disk_size_gb
  disk_type                     = var.gke_disk_type
  master_ipv4_cidr_block        = var.gke_master_ipv4_cidr_block
  master_authorized_cidr_blocks = var.gke_master_authorized_cidr_blocks

  depends_on = [google_project_service.required]
}

# ---------------------------------------------------------------------------
# Supporting infrastructure: Artifact Registry
# ---------------------------------------------------------------------------

module "supporting_infra" {
  source = "../../modules/supporting_infra"

  project_id    = var.project_id
  region        = var.region
  repository_id = var.artifact_registry_repository_id
  labels        = local.common_labels

  depends_on = [google_project_service.required]
}

# ---------------------------------------------------------------------------
# GitHub OIDC: Workload Identity Federation for GitHub Actions
# ---------------------------------------------------------------------------

module "github_oidc" {
  source = "../../modules/github_oidc"

  project_id                      = var.project_id
  naming_prefix                   = var.naming_prefix
  environment                     = var.environment
  github_owner                    = var.github_owner
  github_repository               = var.github_repository
  github_environment              = var.github_environment
  region                          = var.region
  artifact_registry_repository_id = var.artifact_registry_repository_id

  # The AR repository must exist before the IAM binding can be created.
  depends_on = [module.supporting_infra, google_project_service.required]
}

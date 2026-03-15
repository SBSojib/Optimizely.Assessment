# ---------------------------------------------------------------------------
# Node pool service account
# ---------------------------------------------------------------------------

resource "google_service_account" "gke_nodes" {
  account_id   = "${var.naming_prefix}-gke-nodes"
  display_name = "GKE node SA for ${var.cluster_name}"
  project      = var.project_id
}

resource "google_service_account" "hello_service" {
  account_id   = "${var.naming_prefix}-hello-svc"
  display_name = "Workload Identity SA for hello-service"
  project      = var.project_id
}

locals {
  node_sa_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/artifactregistry.reader",
  ]

  hello_service_ksa_member = "serviceAccount:${var.project_id}.svc.id.goog[${var.hello_service_namespace}/${var.hello_service_service_account}]"
}

resource "google_project_iam_member" "gke_node_roles" {
  for_each = toset(local.node_sa_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_service_account_iam_member" "hello_service_workload_identity" {
  service_account_id = google_service_account.hello_service.name
  role               = "roles/iam.workloadIdentityUser"
  member             = local.hello_service_ksa_member
}

# ---------------------------------------------------------------------------
# GKE cluster
# ---------------------------------------------------------------------------

resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  project  = var.project_id
  location = var.zone

  network    = var.network_id
  subnetwork = var.subnet_id

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_secondary_range_name
    services_secondary_range_name = var.services_secondary_range_name
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }

  dynamic "master_authorized_networks_config" {
    for_each = length(var.master_authorized_cidr_blocks) > 0 ? [1] : []
    content {
      dynamic "cidr_blocks" {
        for_each = var.master_authorized_cidr_blocks
        content {
          cidr_block   = cidr_blocks.value.cidr_block
          display_name = cidr_blocks.value.display_name
        }
      }
    }
  }

  datapath_provider = "ADVANCED_DATAPATH"

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  monitoring_config {
    managed_prometheus {
      enabled = true
    }
  }

  release_channel {
    channel = "REGULAR"
  }

  remove_default_node_pool = true
  initial_node_count       = 1
  deletion_protection      = var.environment == "prod"

  resource_labels = var.labels

  # GKE API returns extra/computed fields that cause benign drift; ignore read-only / API-managed.
  lifecycle {
    ignore_changes = [
      monitoring_config,
      release_channel,   # master version drifts with REGULAR channel
      resource_labels,   # GCP/addons can add labels; we set var.labels but API may add more
    ]
  }
}

# ---------------------------------------------------------------------------
# Primary node pool
# ---------------------------------------------------------------------------

resource "google_container_node_pool" "primary" {
  name     = var.node_pool_name
  project  = var.project_id
  location = var.zone
  cluster  = google_container_cluster.primary.name

  node_count = var.node_count

  node_config {
    machine_type    = var.machine_type
    disk_size_gb    = var.disk_size_gb
    disk_type       = var.disk_type
    service_account = google_service_account.gke_nodes.email

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    labels = merge(var.labels, {
      node_pool = var.node_pool_name
    })

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }
}

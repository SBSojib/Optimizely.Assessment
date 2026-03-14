# ---------------------------------------------------------------------------
# VPC
# ---------------------------------------------------------------------------

resource "google_compute_network" "vpc" {
  name                    = var.vpc_name
  project                 = var.project_id
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  description             = "Custom VPC for GKE workloads – no default subnets"
}

# ---------------------------------------------------------------------------
# Subnet (GKE-ready with secondary ranges)
# ---------------------------------------------------------------------------

resource "google_compute_subnetwork" "gke" {
  name                     = var.subnet_name
  project                  = var.project_id
  region                   = var.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = var.subnet_cidr
  private_ip_google_access = true
  description              = "GKE node subnet with pod/service secondary ranges and Private Google Access"

  secondary_ip_range {
    range_name    = var.pods_secondary_range_name
    ip_cidr_range = var.pods_secondary_cidr
  }

  secondary_ip_range {
    range_name    = var.services_secondary_range_name
    ip_cidr_range = var.services_secondary_cidr
  }
}

# ---------------------------------------------------------------------------
# Cloud Router + Cloud NAT (scoped to GKE subnet only)
# ---------------------------------------------------------------------------

resource "google_compute_router" "nat_router" {
  name        = "${var.vpc_name}-router"
  project     = var.project_id
  region      = var.region
  network     = google_compute_network.vpc.id
  description = "Router for Cloud NAT egress from GKE private nodes"
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.vpc_name}-nat"
  project                            = var.project_id
  region                             = var.region
  router                             = google_compute_router.nat_router.name
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.gke.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# ---------------------------------------------------------------------------
# Firewall rules
# ---------------------------------------------------------------------------

resource "google_compute_firewall" "allow_iap_ssh" {
  name        = "${var.vpc_name}-allow-iap-ssh"
  project     = var.project_id
  network     = google_compute_network.vpc.id
  description = "Allow SSH via IAP tunnel – secure alternative to public SSH access"
  direction   = "INGRESS"
  priority    = 1000

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_firewall" "allow_health_checks" {
  name        = "${var.vpc_name}-allow-health-checks"
  project     = var.project_id
  network     = google_compute_network.vpc.id
  description = "Allow GCP load balancer and Ingress health check probes"
  direction   = "INGRESS"
  priority    = 1000

  allow {
    protocol = "tcp"
  }

  source_ranges = [
    "35.191.0.0/16",
    "130.211.0.0/22",
  ]
}

resource "google_compute_firewall" "deny_all_ingress" {
  name        = "${var.vpc_name}-deny-all-ingress"
  project     = var.project_id
  network     = google_compute_network.vpc.id
  description = "Explicit deny-all ingress – documents security posture (mirrors implied rule)"
  direction   = "INGRESS"
  priority    = 65534

  deny {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]
}

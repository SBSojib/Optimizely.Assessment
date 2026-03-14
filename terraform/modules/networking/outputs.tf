output "vpc_id" {
  description = "ID of the VPC network"
  value       = google_compute_network.vpc.id
}

output "vpc_name" {
  description = "Name of the VPC network"
  value       = google_compute_network.vpc.name
}

output "vpc_self_link" {
  description = "Self link of the VPC network"
  value       = google_compute_network.vpc.self_link
}

output "subnet_id" {
  description = "ID of the GKE subnet"
  value       = google_compute_subnetwork.gke.id
}

output "subnet_name" {
  description = "Name of the GKE subnet"
  value       = google_compute_subnetwork.gke.name
}

output "pods_secondary_range_name" {
  description = "Name of the pods secondary IP range"
  value       = var.pods_secondary_range_name
}

output "services_secondary_range_name" {
  description = "Name of the services secondary IP range"
  value       = var.services_secondary_range_name
}

output "router_name" {
  description = "Name of the Cloud Router"
  value       = google_compute_router.nat_router.name
}

output "nat_name" {
  description = "Name of the Cloud NAT gateway"
  value       = google_compute_router_nat.nat.name
}

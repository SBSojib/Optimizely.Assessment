output "cluster_id" {
  description = "Unique identifier of the GKE cluster"
  value       = google_container_cluster.primary.id
}

output "cluster_name" {
  description = "Name of the GKE cluster"
  value       = google_container_cluster.primary.name
}

output "cluster_endpoint" {
  description = "Endpoint of the GKE cluster control plane"
  value       = google_container_cluster.primary.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Base64-encoded CA certificate of the cluster"
  value       = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "node_pool_name" {
  description = "Name of the primary node pool"
  value       = google_container_node_pool.primary.name
}

output "node_service_account_email" {
  description = "Email of the GKE node service account"
  value       = google_service_account.gke_nodes.email
}

output "hello_service_gsa_email" {
  description = "Email of the Google service account bound to hello-service via Workload Identity"
  value       = google_service_account.hello_service.email
}

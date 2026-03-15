output "cluster_endpoint" {
  description = "GKE cluster control plane endpoint"
  value       = module.gke.cluster_endpoint
  sensitive   = true
}

output "node_pool_name" {
  description = "Name of the GKE primary node pool"
  value       = module.gke.node_pool_name
}

output "artifact_registry_url" {
  description = "URL of the Artifact Registry Docker repository"
  value       = module.supporting_infra.artifact_registry_url
}

output "cluster_name" {
  description = "Name of the GKE cluster"
  value       = module.gke.cluster_name
}

output "cluster_ca_certificate" {
  description = "Base64-encoded CA certificate for the GKE cluster"
  value       = module.gke.cluster_ca_certificate
  sensitive   = true
}

output "node_service_account_email" {
  description = "Email of the GKE node service account"
  value       = module.gke.node_service_account_email
}

output "hello_service_gsa_email" {
  description = "Google service account bound to the hello-service Kubernetes service account via Workload Identity"
  value       = module.gke.hello_service_gsa_email
}

output "vpc_name" {
  description = "Name of the VPC network"
  value       = module.networking.vpc_name
}

output "subnet_name" {
  description = "Name of the GKE subnet"
  value       = module.networking.subnet_name
}

# --- GitHub OIDC / Workload Identity Federation ---

output "workload_identity_provider_name" {
  description = "Full WIF provider resource name — set as the WORKLOAD_IDENTITY_PROVIDER secret in the GitHub Actions 'dev' environment"
  value       = module.github_oidc.workload_identity_provider_name
}

output "workload_identity_pool_name" {
  description = "Full WIF pool resource name"
  value       = module.github_oidc.workload_identity_pool_name
}

output "github_deployer_service_account_email" {
  description = "Deployer SA email — set as the GCP_SERVICE_ACCOUNT secret in the GitHub Actions 'dev' environment"
  value       = module.github_oidc.github_deployer_service_account_email
}

output "github_deployer_principal_set" {
  description = "principalSet URI for the federated GitHub identity — useful for debugging WIF trust or adding further resource-level IAM bindings"
  value       = module.github_oidc.github_deployer_principal_set
}

output "github_drift_service_account_email" {
  description = "Drift-detection SA email — set as DRIFT_GCP_SERVICE_ACCOUNT secret in the GitHub Actions 'dev' environment for the terraform-drift workflow"
  value       = module.github_oidc.github_drift_service_account_email
}

# --- Alerting ---

output "alert_notification_channel" {
  description = "Cloud Monitoring notification channel resource name"
  value       = module.alerting.notification_channel_name
}

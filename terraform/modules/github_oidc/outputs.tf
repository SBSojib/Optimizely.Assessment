output "workload_identity_pool_name" {
  description = "Full resource name of the Workload Identity Pool (projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/POOL_ID)"
  value       = google_iam_workload_identity_pool.github.name
}

output "workload_identity_provider_name" {
  description = "Full resource name of the WIF provider — set this as the WORKLOAD_IDENTITY_PROVIDER secret in the GitHub Actions environment"
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "github_deployer_service_account_email" {
  description = "Email of the GitHub Actions deployer service account — set this as the GCP_SERVICE_ACCOUNT secret in the GitHub Actions environment"
  value       = google_service_account.github_deployer.email
}

output "github_deployer_principal_set" {
  description = "principalSet URI representing all federated GitHub identities for this repository. Useful for additional resource-level IAM bindings or debugging WIF trust."
  value       = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_owner}/${var.github_repository}"
}

output "github_drift_service_account_email" {
  description = "Email of the drift-detection SA — set as DRIFT_GCP_SERVICE_ACCOUNT secret in the GitHub Actions environment (used by terraform-drift workflow)"
  value       = google_service_account.github_drift.email
}

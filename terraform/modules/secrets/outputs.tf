output "secret_resource_names" {
  description = "Map of secret ID to its full Secret Manager resource name"
  value       = { for k, v in google_secret_manager_secret.app_secrets : k => v.id }
}

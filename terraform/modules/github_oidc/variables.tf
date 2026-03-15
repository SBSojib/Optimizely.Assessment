variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "naming_prefix" {
  description = "Prefix used in resource names for consistent naming"
  type        = string
}

variable "pool_id_suffix" {
  description = "Optional suffix for Workload Identity pool and provider IDs. Use to avoid 409 when the original pool is soft-deleted (e.g. \"-v2\"). Leave empty for normal use."
  type        = string
  default     = ""
}

variable "environment" {
  description = "Deployment environment name (e.g., dev). Used in resource display names."
  type        = string
}

variable "github_owner" {
  description = "GitHub organisation or user that owns the repository (e.g., SBSojib)"
  type        = string
}

variable "github_repository" {
  description = "GitHub repository name, without the owner prefix (e.g., Optimizely.Assessment)"
  type        = string
}

variable "github_environment" {
  description = "GitHub Actions Environment name whose OIDC tokens are trusted (e.g., dev). Must match the 'environment:' field in the workflow job."
  type        = string
}

variable "region" {
  description = "GCP region where Artifact Registry is deployed — used to scope the AR IAM binding"
  type        = string
}

variable "artifact_registry_repository_id" {
  description = "ID of the Artifact Registry Docker repository the deployer SA is allowed to push to"
  type        = string
}

variable "terraform_state_bucket_name" {
  description = "Name of the GCS bucket holding Terraform state. Used to grant the drift-detection SA read access. Omit or set to null to skip GCS state access for drift."
  type        = string
  default     = null
}

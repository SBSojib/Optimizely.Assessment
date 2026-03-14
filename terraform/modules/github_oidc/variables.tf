variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "naming_prefix" {
  description = "Prefix used in resource names for consistent naming"
  type        = string
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

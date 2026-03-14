variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region for the Terraform state bucket"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "terraform_state_bucket_name" {
  description = "Name of the GCS bucket for Terraform remote state"
  type        = string
}

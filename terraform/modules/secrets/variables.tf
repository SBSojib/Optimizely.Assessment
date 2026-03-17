variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "secret_ids" {
  description = "List of Secret Manager secret IDs to create (shell only — values are populated manually via gcloud)"
  type        = list(string)
}

variable "labels" {
  description = "Labels to apply to secret resources"
  type        = map(string)
  default     = {}
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "naming_prefix" {
  description = "Prefix used in resource names for consistent naming"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g. dev, staging, prod)"
  type        = string
}

variable "cluster_name" {
  description = "GKE cluster name — used to scope alert filters to this cluster"
  type        = string
}

variable "app_namespace" {
  description = "Kubernetes namespace of the application workload"
  type        = string
}

variable "alert_notification_email" {
  description = "Email address for Cloud Monitoring alert notifications. The recipient must verify the address in the GCP Console after the first apply."
  type        = string
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "vpc_name" {
  description = "Name of the VPC network"
  type        = string
}

variable "subnet_name" {
  description = "Name of the GKE subnet"
  type        = string
}

variable "subnet_cidr" {
  description = "Primary CIDR range for the subnet"
  type        = string
}

variable "pods_secondary_range_name" {
  description = "Name of the secondary IP range for GKE pods"
  type        = string
}

variable "pods_secondary_cidr" {
  description = "CIDR for the GKE pods secondary range"
  type        = string
}

variable "services_secondary_range_name" {
  description = "Name of the secondary IP range for GKE services"
  type        = string
}

variable "services_secondary_cidr" {
  description = "CIDR for the GKE services secondary range"
  type        = string
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default     = {}
}

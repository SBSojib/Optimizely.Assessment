variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "zone" {
  description = "GCP zone for the zonal cluster"
  type        = string
}

variable "cluster_name" {
  description = "Name of the GKE cluster"
  type        = string
}

variable "network_id" {
  description = "VPC network ID for the cluster"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the cluster"
  type        = string
}

variable "pods_secondary_range_name" {
  description = "Name of the secondary range for pods"
  type        = string
}

variable "services_secondary_range_name" {
  description = "Name of the secondary range for services"
  type        = string
}

variable "node_pool_name" {
  description = "Name of the primary node pool"
  type        = string
}

variable "machine_type" {
  description = "Machine type for node pool instances"
  type        = string
}

variable "node_count" {
  description = "Number of nodes per zone in the node pool"
  type        = number
}

variable "disk_size_gb" {
  description = "Boot disk size in GB for node pool instances"
  type        = number
}

variable "disk_type" {
  description = "Boot disk type for node pool instances"
  type        = string
}

variable "master_ipv4_cidr_block" {
  description = "CIDR block for the GKE master network (must be /28)"
  type        = string
}

variable "naming_prefix" {
  description = "Naming prefix for associated resources"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "hello_service_namespace" {
  description = "Namespace used by the hello-service workload"
  type        = string
}

variable "hello_service_service_account" {
  description = "Kubernetes service account name used by hello-service"
  type        = string
}

variable "master_authorized_cidr_blocks" {
  description = "CIDRs allowed to reach the GKE control plane public endpoint. Empty list disables the restriction."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
}

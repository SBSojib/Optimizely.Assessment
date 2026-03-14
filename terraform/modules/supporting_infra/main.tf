resource "google_artifact_registry_repository" "docker" {
  repository_id = var.repository_id
  project       = var.project_id
  location      = var.region
  format        = "DOCKER"
  description   = "Docker container images for ${var.repository_id}"

  labels = var.labels
}

# ---------------------------------------------------------------------------
# Secret Manager: secret shells
# ---------------------------------------------------------------------------

resource "google_secret_manager_secret" "app_secrets" {
  for_each = toset(var.secret_ids)

  secret_id = each.value
  project   = var.project_id

  replication {
    auto {}
  }

  labels = var.labels
}

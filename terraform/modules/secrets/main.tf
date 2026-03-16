# ---------------------------------------------------------------------------
# Secret Manager: secret shells + IAM
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

resource "google_secret_manager_secret_iam_member" "accessor" {
  for_each = toset(var.secret_ids)

  secret_id = google_secret_manager_secret.app_secrets[each.value].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.accessor_service_account_email}"
}

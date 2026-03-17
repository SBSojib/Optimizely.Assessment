# ---------------------------------------------------------------------------
# Workload Identity Pool
# ---------------------------------------------------------------------------
# A pool is a logical grouping for external identity providers. All GitHub
# OIDC tokens issued for this project flow through this pool.
# ---------------------------------------------------------------------------

resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "${var.naming_prefix}-gh-pool${var.pool_id_suffix}"
  display_name              = "GitHub Actions pool"
  description               = "WIF pool for GitHub Actions CI/CD (${var.github_owner}/${var.github_repository})"
  project                   = var.project_id

  lifecycle {
    prevent_destroy = true
  }
}

# ---------------------------------------------------------------------------
# GitHub OIDC Provider
# ---------------------------------------------------------------------------
# Tells GCP how to validate incoming GitHub OIDC JWTs and which claims to
# surface as Google credential attributes.
#
# attribute_condition: reject any token that is NOT from this exact repository
# AND GitHub Actions environment. This is enforced at the provider level —
# tokens from other repos or environments never receive a GCP credential,
# even if someone has the pool/provider URLs.
# ---------------------------------------------------------------------------

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "${var.naming_prefix}-github${var.pool_id_suffix}"
  display_name                       = "GitHub Actions OIDC"
  description                        = "Trusts GitHub OIDC tokens for ${var.github_owner}/${var.github_repository}, environment: ${var.github_environment}"
  project                            = var.project_id

  # Reject tokens that do not originate from this repository AND the
  # specific GitHub Actions environment (the 'environment:' key in the workflow
  # job). Using the environment claim is tighter than a branch check: only
  # jobs that explicitly declare 'environment: dev' can authenticate.
  attribute_condition = "assertion.repository == \"${var.github_owner}/${var.github_repository}\" && assertion.environment == \"${var.github_environment}\""

  attribute_mapping = {
    # google.subject is mandatory — it is set to the token's 'sub' claim, which
    # encodes repo + ref/environment (e.g., repo:OWNER/REPO:environment:dev).
    "google.subject" = "assertion.sub"

    # Custom attributes: available in IAM conditions and principalSet URIs.
    "attribute.actor"            = "assertion.actor"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
    "attribute.ref"              = "assertion.ref"
    "attribute.environment"      = "assertion.environment"
  }

  oidc {
    # GitHub's well-known OIDC issuer for Actions.
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# ---------------------------------------------------------------------------
# GitHub Actions deployer service account
# ---------------------------------------------------------------------------
# This SA is what GitHub Actions impersonates. It holds the minimum IAM roles
# needed for the CD pipeline: push to Artifact Registry + deploy to GKE.
# No key is ever created for it — access is entirely via WIF token exchange.
# ---------------------------------------------------------------------------

resource "google_service_account" "github_deployer" {
  account_id   = "${var.naming_prefix}-gh-deployer"
  display_name = "GitHub Actions deployer (${var.environment})"
  description  = "Impersonated by GitHub Actions via WIF to push images and deploy to GKE. No long-lived key."
  project      = var.project_id
}

# ---------------------------------------------------------------------------
# Allow the GitHub federated identity to impersonate the deployer SA
# ---------------------------------------------------------------------------
# roles/iam.workloadIdentityUser on the SA grants the right to call
# GenerateAccessToken / GenerateIdToken, completing the WIF exchange.
#
# The principalSet matches ALL tokens in this pool where attribute.repository
# equals the configured GitHub repository. The attribute_condition on the
# provider (above) ensures only the correct environment can reach this pool,
# so the combination is tightly scoped without being fragile.
# ---------------------------------------------------------------------------

resource "google_service_account_iam_member" "github_wif_impersonation" {
  service_account_id = google_service_account.github_deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_owner}/${var.github_repository}"
}

# ---------------------------------------------------------------------------
# IAM: Artifact Registry writer — scoped to the specific repository
# ---------------------------------------------------------------------------
# Binding at the AR repository level (not project level) means the deployer
# SA can only push to this one repository, not to any other repo in the project.
# ---------------------------------------------------------------------------

resource "google_artifact_registry_repository_iam_member" "github_deployer_ar_writer" {
  project    = var.project_id
  location   = var.region
  repository = var.artifact_registry_repository_id
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.github_deployer.email}"
}

# ---------------------------------------------------------------------------
# IAM: GKE cluster access
# ---------------------------------------------------------------------------
# roles/container.developer grants:
#   1. container.clusters.get — required for `gcloud container clusters get-credentials`
#   2. GKE automatic IAM-to-RBAC mapping — GKE binds this identity to the
#      Kubernetes 'edit' ClusterRole, giving it create/update rights on
#      Deployments, Services, ConfigMaps, etc. — sufficient for helm upgrade.
#
# This is a project-level binding because GKE does not support fine-grained
# resource-level scoping for container.developer.
# ---------------------------------------------------------------------------

resource "google_project_iam_member" "github_deployer_gke" {
  project = var.project_id
  role    = "roles/container.developer"
  member  = "serviceAccount:${google_service_account.github_deployer.email}"
}

# ---------------------------------------------------------------------------
# GitHub Actions drift-detection service account (read-only)
# ---------------------------------------------------------------------------
# Used by the Terraform drift detection workflow. Holds roles/viewer and
# read access to the Terraform state bucket only. No deploy or write rights.
# Same WIF pool/provider — workflows choose which SA to impersonate via secrets.
# ---------------------------------------------------------------------------

resource "google_service_account" "github_drift" {
  account_id   = "${var.naming_prefix}-gh-drift"
  display_name = "GitHub Actions drift detection (${var.environment})"
  description  = "Read-only SA for terraform plan (drift detection). Impersonated via WIF. No long-lived key."
  project      = var.project_id
}

resource "google_service_account_iam_member" "github_drift_wif_impersonation" {
  service_account_id = google_service_account.github_drift.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_owner}/${var.github_repository}"
}

resource "google_project_iam_member" "github_drift_viewer" {
  project = var.project_id
  role    = "roles/viewer"
  member  = "serviceAccount:${google_service_account.github_drift.email}"
}

resource "google_project_iam_member" "github_drift_gke_cluster_viewer" {
  project = var.project_id
  role    = "roles/container.clusterViewer"
  member  = "serviceAccount:${google_service_account.github_drift.email}"
}

# Custom role: read state objects + read bucket IAM (so plan can refresh google_storage_bucket_iam_member).
resource "google_project_iam_custom_role" "terraform_state_read" {
  count       = var.terraform_state_bucket_name != null ? 1 : 0
  role_id     = "terraformStateRead"
  title       = "Terraform state read + getIamPolicy"
  description = "Read state objects and bucket IAM for drift plan refresh. No setIamPolicy."
  project     = var.project_id
  permissions = [
    "storage.objects.get",
    "storage.objects.list",
    "storage.buckets.getIamPolicy",
  ]
}

# State bucket: grant drift SA the role above (plan uses -lock=false).
resource "google_storage_bucket_iam_member" "github_drift_state" {
  count  = var.terraform_state_bucket_name != null ? 1 : 0
  bucket = var.terraform_state_bucket_name
  role   = "projects/${var.project_id}/roles/${google_project_iam_custom_role.terraform_state_read[0].role_id}"
  member = "serviceAccount:${google_service_account.github_drift.email}"
}

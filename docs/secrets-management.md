# Secrets Management

## Overview

Secret values (API keys, connection strings, etc.) are stored in **GCP Secret Manager** and read at runtime by the application via the official SDK. Authentication is automatic through **GKE Workload Identity** — no JSON keys or Kubernetes Secrets are involved.

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  GCP Project                                                     │
│                                                                  │
│  Secret Manager                                                  │
│  ┌─────────────────────┐     IAM: secretAccessor                 │
│  │ hello-svc-api-key   │◄──── opti-devops-hello-svc (GSA)        │
│  │ (value set via CLI) │                  ▲                      │
│  └─────────────────────┘                  │ Workload Identity    │
│                                           │                      │
│  GKE Cluster                              │                      │
│  ┌────────────────────────────────────────┤──────────────────┐   │
│  │  hello-app namespace                   │                  │   │
│  │  ┌──────────────────────────────┐      │                  │   │
│  │  │ hello-service pod            │      │                  │   │
│  │  │  KSA: hello-service-sa ──────┘      │                  │   │
│  │  │  env: GCP_PROJECT_ID                │                  │   │
│  │  │  env: SECRET_API_KEY ──► SDK call ──┘                  │   │
│  │  └──────────────────────────────┘                         │   │
│  └───────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────┘
```

## How It Works

1. **Terraform** creates Secret Manager secret shells (no values) and grants `roles/secretmanager.secretAccessor` to the hello-service GSA
2. **Operator** populates secret values manually via `gcloud` (one-time, outside git)
3. **Helm** injects `SECRET_<X>=<secret-id>` env vars into the pod and, when secret references are enabled, also passes `GCP_PROJECT_ID`
4. **App** at startup scans for `SECRET_*` env vars, calls Secret Manager to resolve each, and exports the value as the corresponding env var (e.g., `SECRET_API_KEY=hello-svc-api-key` becomes `API_KEY=<actual value>`)
5. **Workload Identity** provides authentication automatically — the pod's KSA is bound to the GSA

## Calling the /hello API

The `/hello` endpoint requires the API key. Send it in one of two ways:

```bash
# Option 1: Authorization header
curl -H "Authorization: Bearer YOUR_API_KEY_VALUE" http://localhost:8080/hello

# Option 2: X-API-Key header
curl -H "X-API-Key: YOUR_API_KEY_VALUE" http://localhost:8080/hello
```

Use the same value you stored in Secret Manager for `hello-svc-api-key`. Without a valid key, requests to `/hello` return **401**. The `/health` and `/metrics` endpoints remain open (no key required).

## Populating Secret Values

After `terraform apply` creates the secret shells:

```bash
# Add or update a secret value
printf "your-actual-secret-value" | \
  gcloud secrets versions add hello-svc-api-key \
    --project=YOUR_PROJECT_ID \
    --data-file=-

# Verify it was stored (shows metadata, not the value)
gcloud secrets versions list hello-svc-api-key \
  --project=YOUR_PROJECT_ID

# Read back the value (for verification only)
gcloud secrets versions access latest \
  --secret=hello-svc-api-key \
  --project=YOUR_PROJECT_ID
```

After populating, restart the deployment to pick up the new value:

```bash
kubectl rollout restart deployment/hello-service -n hello-app
```

## Adding a New Secret

1. Add the secret ID to `secrets.auto.tfvars`:

```hcl
secret_manager_secret_ids = ["hello-svc-api-key", "hello-svc-db-password"]
```

2. Run `terraform apply` to create the shell and IAM binding

3. Populate the value:

```bash
printf "actual-db-password" | \
  gcloud secrets versions add hello-svc-db-password \
    --project=YOUR_PROJECT_ID \
    --data-file=-
```

4. Add the mapping in Helm values (or `--set` in the deploy workflow):

```yaml
secrets:
  enabled: true
  refs:
    API_KEY: hello-svc-api-key
    DB_PASSWORD: hello-svc-db-password
```

5. The app will automatically pick up `DB_PASSWORD` on the next deployment

## Security Properties

| Property | How It's Achieved |
|----------|-------------------|
| No secrets in git | Values populated via `gcloud`, never in tfvars or Helm values |
| No secrets in Terraform state | Terraform only creates the secret shell, not versions |
| No secrets in Kubernetes | App reads directly from Secret Manager — no K8s Secret objects |
| No long-lived credentials | Workload Identity provides short-lived tokens automatically |
| Audit trail | Cloud Audit Logs records every secret access |
| Runtime access | The hello-service GSA has the Secret Manager access it needs for runtime retrieval |
| Explicit failure mode | If secret references are configured but Secret Manager access fails, startup fails fast rather than serving with partial configuration |

## Design Decision: Why Not CSI Driver or External Secrets Operator?

| Approach | Pros | Cons | Verdict |
|----------|------|------|---------|
| **SDK (chosen)** | Zero extra infrastructure, Google-recommended, single source of truth | Per-service SDK dependency | Best for small scope |
| **CSI Driver** | K8s-native, auto-sync, no app code | DaemonSet on every node, SecretProviderClass CRDs | Overkill for 1 service |
| **External Secrets** | Declarative K8s resources, multi-provider | Operator + CRDs to install and maintain | Overkill for 1 service |

For a platform with dozens of services, External Secrets Operator is the standard choice. For this single-service assessment, the direct SDK approach demonstrates the same security principles with fewer moving parts.

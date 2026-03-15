# ---------------------------------------------------------------------------
# Notification channel
# ---------------------------------------------------------------------------

resource "google_monitoring_notification_channel" "email" {
  project      = var.project_id
  display_name = "${var.naming_prefix} Alert Notifications (${var.environment})"
  type         = "email"

  labels = {
    email_address = var.alert_notification_email
  }
}

# ---------------------------------------------------------------------------
# Log-based metric: count severity >= ERROR from the app namespace
# ---------------------------------------------------------------------------

resource "google_logging_metric" "hello_service_errors" {
  project = var.project_id
  name    = "${var.naming_prefix}-hello-service-errors"

  filter = join(" AND ", [
    "resource.type=\"k8s_container\"",
    "resource.labels.namespace_name=\"${var.app_namespace}\"",
    "resource.labels.cluster_name=\"${var.cluster_name}\"",
    "severity>=ERROR",
  ])

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}

# ---------------------------------------------------------------------------
# Alert 1 — Container restart rate (CrashLoopBackOff / OOMKilled)
# ---------------------------------------------------------------------------

resource "google_monitoring_alert_policy" "container_restarts" {
  project      = var.project_id
  display_name = "[${var.environment}] Container Restart Rate — hello-service"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "Container restarts > 3 in 10 min"

    condition_threshold {
      filter = join(" AND ", [
        "resource.type = \"k8s_container\"",
        "resource.labels.namespace_name = \"${var.app_namespace}\"",
        "resource.labels.cluster_name = \"${var.cluster_name}\"",
        "metric.type = \"kubernetes.io/container/restart_count\"",
      ])

      comparison      = "COMPARISON_GT"
      threshold_value = 3
      duration        = "0s"

      aggregations {
        alignment_period   = "600s"
        per_series_aligner = "ALIGN_DELTA"
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.name]

  alert_strategy {
    auto_close = "1800s"
  }

  documentation {
    content = join("\n", [
      "**Container restarts detected in the hello-service namespace.**",
      "",
      "This typically indicates CrashLoopBackOff, OOMKilled, or failing health probes.",
      "",
      "Investigation steps:",
      "1. `kubectl get pods -n ${var.app_namespace}` — check pod status and restart counts",
      "2. `kubectl describe pod <pod> -n ${var.app_namespace}` — look for OOMKilled or probe failures",
      "3. `kubectl logs <pod> -n ${var.app_namespace} --previous` — check logs from the crashed container",
      "4. Check Cloud Logging for the namespace for correlated errors",
    ])
    mime_type = "text/markdown"
  }
}

# ---------------------------------------------------------------------------
# Alert 2 — Memory utilization near limit (pre-OOMKill warning)
# ---------------------------------------------------------------------------

resource "google_monitoring_alert_policy" "memory_utilization" {
  project      = var.project_id
  display_name = "[${var.environment}] Memory Utilization High — hello-service"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "Container memory > 85% of limit for 5 min"

    condition_threshold {
      filter = join(" AND ", [
        "resource.type = \"k8s_container\"",
        "resource.labels.namespace_name = \"${var.app_namespace}\"",
        "resource.labels.cluster_name = \"${var.cluster_name}\"",
        "metric.type = \"kubernetes.io/container/memory/limit_utilization\"",
      ])

      comparison      = "COMPARISON_GT"
      threshold_value = 0.85
      duration        = "300s"

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.name]

  alert_strategy {
    auto_close = "1800s"
  }

  documentation {
    content = join("\n", [
      "**Container memory usage is above 85% of its configured limit.**",
      "",
      "This is a leading indicator before OOMKill. If not addressed, the container",
      "will be killed and restarted, which triggers the container-restart alert.",
      "",
      "Investigation steps:",
      "1. `kubectl top pods -n ${var.app_namespace}` — current memory usage",
      "2. Check for memory leaks or unexpected traffic spikes",
      "3. Consider increasing the memory limit in the Helm values if sustained",
    ])
    mime_type = "text/markdown"
  }
}

# ---------------------------------------------------------------------------
# Alert 3 — Application error log rate
# ---------------------------------------------------------------------------

resource "google_monitoring_alert_policy" "error_log_rate" {
  project      = var.project_id
  display_name = "[${var.environment}] Error Log Rate — hello-service"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "Error logs > 5 in 5 min"

    condition_threshold {
      filter = join(" AND ", [
        "resource.type = \"k8s_container\"",
        "metric.type = \"logging.googleapis.com/user/${google_logging_metric.hello_service_errors.name}\"",
      ])

      comparison      = "COMPARISON_GT"
      threshold_value = 5
      duration        = "0s"

      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_DELTA"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["resource.labels.namespace_name"]
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.name]

  alert_strategy {
    auto_close = "1800s"
  }

  documentation {
    content = join("\n", [
      "**Elevated error rate detected in hello-service logs.**",
      "",
      "This fires when severity >= ERROR log entries exceed the threshold,",
      "which may indicate application exceptions, dependency failures, or",
      "degraded behavior that does not crash the pod.",
      "",
      "Investigation steps:",
      "1. Check Cloud Logging: resource.type=\"k8s_container\" resource.labels.namespace_name=\"${var.app_namespace}\" severity>=ERROR",
      "2. Look for patterns — are errors from one pod or all replicas?",
      "3. Check recent deployments or config changes",
    ])
    mime_type = "text/markdown"
  }
}

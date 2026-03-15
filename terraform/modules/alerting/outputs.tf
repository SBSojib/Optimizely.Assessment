output "notification_channel_name" {
  description = "Full resource name of the email notification channel"
  value       = google_monitoring_notification_channel.email.name
}

output "alert_policy_names" {
  description = "Map of alert policy keys to their full resource names"
  value = {
    container_restarts = google_monitoring_alert_policy.container_restarts.name
    memory_utilization = google_monitoring_alert_policy.memory_utilization.name
    error_log_rate     = google_monitoring_alert_policy.error_log_rate.name
  }
}

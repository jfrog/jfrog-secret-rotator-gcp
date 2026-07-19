# (c) JFrog Ltd. (2026)

output "project_number" {
  description = "GCP project number (used in JFrog identity mapping aud claim)."
  value       = data.google_project.current.number
}

output "function_service_account_email" {
  description = "Service account email for the rotation function (used in JFrog identity mapping email claim)."
  value       = google_service_account.rotator.email
}

output "secret_id" {
  description = "Secret Manager secret ID."
  value       = google_secret_manager_secret.jfrog_token.secret_id
}

output "secret_resource_name" {
  description = "Full Secret Manager resource name."
  value       = google_secret_manager_secret.jfrog_token.id
}

output "default_audience" {
  description = "Default OIDC audience when AUDIENCE env var is not set (use in JFrog identity mapping aud claim)."
  value       = local.oidc_audience
}

output "jfrog_token_expires_in" {
  description = "Effective JFrog token expires_in (seconds) for the identity mapping."
  value       = local.jfrog_token_expires_in
}

output "create_jfrog_oidc" {
  description = "Whether Terraform manages the JFrog OIDC provider and identity mapping."
  value       = var.create_jfrog_oidc
}

output "configured_audience" {
  description = "Effective OIDC audience configured on the function (empty string means default_audience is used at runtime)."
  value       = var.audience
}

output "pubsub_topic_id" {
  description = "Pub/Sub topic ID for rotation notifications."
  value       = google_pubsub_topic.rotation.id
}

output "cloud_function_name" {
  description = "Deployed Cloud Function name."
  value       = google_cloudfunctions2_function.rotator.name
}

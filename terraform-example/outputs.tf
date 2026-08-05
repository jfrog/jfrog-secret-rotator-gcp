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

output "create_cloud_run_example" {
  description = "Whether Terraform manages the optional Artifact Registry connector and Cloud Run Nginx example."
  value       = var.create_cloud_run_example
}

output "connector_repository_id" {
  description = "Artifact Registry connector repository ID (null when create_cloud_run_example is false)."
  value       = try(google_artifact_registry_repository.jfrog_connector[0].repository_id, null)
}

output "connector_image" {
  description = "Image path Cloud Run pulls via the connector (null when create_cloud_run_example is false)."
  value       = var.create_cloud_run_example ? local.connector_image : null
}

output "cloud_run_service_url" {
  description = "URL of the optional Cloud Run Nginx example (null when create_cloud_run_example is false)."
  value       = try(google_cloud_run_v2_service.nginx_example[0].uri, null)
}

output "jfrog_docker_local_key" {
  description = "JFrog local Docker repository key used by the Cloud Run example."
  value       = var.create_cloud_run_example ? local.jfrog_docker_local_key : null
}

output "jfrog_docker_remote_key" {
  description = "JFrog remote Docker Hub repository key used by the Cloud Run example."
  value       = var.create_cloud_run_example ? local.jfrog_docker_remote_key : null
}

output "jfrog_docker_virtual_key" {
  description = "JFrog virtual Docker repository key used as the connector upstream."
  value       = var.create_cloud_run_example ? local.jfrog_docker_virtual_key : null
}

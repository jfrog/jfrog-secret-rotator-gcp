variable "project_id" {
  description = "GCP project ID where resources will be created."
  type        = string
}

variable "region" {
  description = "GCP region for the Cloud Function and related resources."
  type        = string
}

variable "secret_name" {
  description = "Secret Manager secret ID for the JFrog access token."
  type        = string
}

variable "pubsub_topic_name" {
  description = "Pub/Sub topic name for Secret Manager rotation notifications."
  type        = string
  default     = "jfrog-secret-rotation"
}

variable "function_name" {
  description = "Name of the Cloud Function (Gen2)."
  type        = string
  default     = "secret-rotation-function"
}

variable "function_service_account_id" {
  description = "Service account ID (short name) used by the rotation function."
  type        = string
  default     = "secret-rotator-sa"
}

variable "rotation_period" {
  description = "Interval between rotation notifications (e.g. \"36000s\" for 10 hours). Minimum 3600s (1 hour)."
  type        = string
}

variable "next_rotation_time" {
  description = "RFC3339 timestamp for the first rotation. Defaults to ~5 minutes after apply if unset."
  type        = string
  default     = null
}

variable "jfrog_host" {
  description = "JFrog platform hostname for OIDC token exchange (e.g. myregistry.jfrog.io)."
  type        = string
}

variable "provider_name" {
  description = "JFrog OIDC integration provider name."
  type        = string
}

variable "audience" {
  description = "Google OIDC audience claim. Leave empty to use the secret resource name (projects/<num>/secrets/<id>)."
  type        = string
  default     = ""
}

variable "prev_secret_action" {
  description = "Action on the previous secret version after rotation: KEEP, DESTROY, or DISABLE."
  type        = string
  default     = "KEEP"

  validation {
    condition     = contains(["KEEP", "DESTROY", "DISABLE"], var.prev_secret_action)
    error_message = "prev_secret_action must be KEEP, DESTROY, or DISABLE."
  }
}

variable "jfrog_debug" {
  description = "Enable debug logging in the rotation function."
  type        = bool
  default     = false
}

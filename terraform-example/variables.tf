# (c) JFrog Ltd. (2026)

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
  description = "RFC3339 timestamp for the first rotation. Defaults to ~6 minutes after plan if unset."
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
  default     = "DESTROY"

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

variable "create_jfrog_oidc" {
  description = "When true, create the JFrog OIDC provider and identity mapping via Terraform. When false, use an existing JFrog OIDC integration — see docs/terraform-setup.md."
  type        = bool
  default     = true
}

variable "jfrog_access_token" {
  description = "JFrog platform admin access token for OIDC resources. Required when create_jfrog_oidc is true unless JFROG_ACCESS_TOKEN is set."
  type        = string
  sensitive   = true
  default     = null
}

variable "bootstrap_jfrog_token" {
  description = "JFrog access token for the initial Secret Manager version. Set this to a valid token so GAR and other consumers can use the secret immediately after apply. Defaults to the placeholder \"dummy-token\" (not a valid token) when not overridden; the rotation function replaces it on the first rotation."
  type        = string
  sensitive   = true
  default     = "dummy-token"
}

variable "jfrog_user" {
  description = "Existing JFrog username for the OIDC identity mapping (token_spec.username). Required when create_jfrog_oidc is true."
  type        = string
  default     = null

  validation {
    condition     = !var.create_jfrog_oidc || (var.jfrog_user != null && var.jfrog_user != "")
    error_message = "jfrog_user is required when create_jfrog_oidc is true."
  }
}

variable "jfrog_token_expires_in" {
  description = "JFrog access token lifetime in seconds for the identity mapping. Defaults to rotation_period × 1.3 when unset."
  type        = number
  default     = null
}

variable "oidc_mapping_name" {
  description = "Name of the JFrog OIDC identity mapping. Defaults to provider_name."
  type        = string
  default     = null
}

variable "oidc_mapping_priority" {
  description = "Priority of the JFrog OIDC identity mapping (lower number = higher priority)."
  type        = number
  default     = 1
}

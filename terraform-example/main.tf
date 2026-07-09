data "google_project" "current" {
  project_id = var.project_id
}

locals {
  next_rotation_time        = coalesce(var.next_rotation_time, timeadd(plantimestamp(), "360s"))
  rotation_period_seconds   = tonumber(regex("^([0-9]+)s$", var.rotation_period)[0])
  oidc_audience             = var.audience != "" ? var.audience : "projects/${data.google_project.current.number}/secrets/${google_secret_manager_secret.jfrog_token.secret_id}"
  jfrog_token_expires_in    = coalesce(var.jfrog_token_expires_in, ceil(local.rotation_period_seconds * 1.3))
  bootstrap_secret_data     = coalesce(var.bootstrap_jfrog_token, var.jfrog_access_token, "pending-first-rotation")

  function_env_vars = merge(
    {
      JFROG_HOST         = var.jfrog_host
      PROVIDER_NAME      = var.provider_name
      PREV_SECRET_ACTION = var.prev_secret_action
      JFROG_DEBUG        = var.jfrog_debug ? "true" : "false"
    },
    var.audience != "" ? { AUDIENCE = var.audience } : {}
  )

  secret_manager_service_agent      = "service-${data.google_project.current.number}@gcp-sa-secretmanager.iam.gserviceaccount.com"
  pubsub_service_agent              = "service-${data.google_project.current.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
  artifact_registry_service_agent   = "service-${data.google_project.current.number}@gcp-sa-artifactregistry.iam.gserviceaccount.com"

  required_apis = [
    "secretmanager.googleapis.com",
    "pubsub.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "run.googleapis.com",
    "eventarc.googleapis.com",
    "artifactregistry.googleapis.com",
    "storage.googleapis.com",
  ]
}

resource "google_project_service" "required" {
  for_each = toset(local.required_apis)

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_project_service_identity" "secretmanager" {
  provider = google-beta
  project  = var.project_id
  service  = "secretmanager.googleapis.com"

  depends_on = [google_project_service.required]
}

resource "google_pubsub_topic" "rotation" {
  name    = var.pubsub_topic_name
  project = var.project_id

  depends_on = [google_project_service.required]
}

resource "google_pubsub_topic_iam_member" "sm_publisher" {
  topic  = google_pubsub_topic.rotation.id
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${local.secret_manager_service_agent}"

  depends_on = [google_project_service_identity.secretmanager]
}

resource "google_secret_manager_secret" "jfrog_token" {
  project   = var.project_id
  secret_id = var.secret_name

  replication {
    auto {}
  }

  topics {
    name = google_pubsub_topic.rotation.id
  }

  rotation {
    rotation_period    = var.rotation_period
    next_rotation_time = local.next_rotation_time
  }

  depends_on = [
    google_pubsub_topic_iam_member.sm_publisher,
  ]
}

resource "google_secret_manager_secret_version" "bootstrap" {
  secret      = google_secret_manager_secret.jfrog_token.id
  secret_data = local.bootstrap_secret_data

  lifecycle {
    ignore_changes = [secret_data]
  }
}

resource "google_secret_manager_secret_iam_member" "artifact_registry_accessor" {
  secret_id = google_secret_manager_secret.jfrog_token.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${local.artifact_registry_service_agent}"

  depends_on = [google_project_service.required]
}

resource "google_service_account" "rotator" {
  account_id   = var.function_service_account_id
  display_name = "Secret Rotation Service Account"
  project      = var.project_id
}

resource "google_project_iam_member" "rotator_secret_admin" {
  project = var.project_id
  role    = "roles/secretmanager.admin"
  member  = "serviceAccount:${google_service_account.rotator.email}"
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "google_storage_bucket" "function_source" {
  name                        = "${var.project_id}-secret-rotator-src-${random_id.bucket_suffix.hex}"
  location                    = var.region
  project                     = var.project_id
  uniform_bucket_level_access = true
  force_destroy               = true

  depends_on = [google_project_service.required]
}

data "archive_file" "function_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../secret-rotator"
  output_path = "${path.module}/.build/function.zip"
}

resource "google_storage_bucket_object" "function_zip" {
  name   = "function-${data.archive_file.function_zip.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_zip.output_path
}

resource "google_cloudfunctions2_function" "rotator" {
  name        = var.function_name
  location    = var.region
  project     = var.project_id
  description = "Rotates a JFrog access token in Secret Manager on schedule"

  build_config {
    runtime     = "python311"
    entry_point = "rotate_secret_handler"

    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_zip.name
      }
    }
  }

  service_config {
    available_memory      = "256M"
    timeout_seconds       = 120
    service_account_email = google_service_account.rotator.email
    environment_variables = local.function_env_vars
  }

  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.rotation.id
    retry_policy   = "RETRY_POLICY_RETRY"
  }

  depends_on = [
    google_project_service.required,
    google_project_iam_member.rotator_secret_admin,
    google_storage_bucket_object.function_zip,
  ]
}

resource "google_cloud_run_v2_service_iam_member" "pubsub_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloudfunctions2_function.rotator.service_config[0].service
  role     = "roles/run.invoker"
  member   = "serviceAccount:${local.pubsub_service_agent}"
}

resource "google_cloud_run_v2_service_iam_member" "eventarc_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloudfunctions2_function.rotator.service_config[0].service
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.rotator.email}"
}

resource "google_service_account_iam_member" "pubsub_token_creator" {
  service_account_id = google_service_account.rotator.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${local.pubsub_service_agent}"
}

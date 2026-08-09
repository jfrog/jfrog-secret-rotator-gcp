# (c) JFrog Ltd. (2026)

# Optional end-to-end example: JFrog local + Docker Hub remote + virtual Docker repos,
# Artifact Registry connector (no_cache), and a public Cloud Run Nginx service that
# pulls nginx:latest through Artifactory (no local image push required).

locals {
  create_cloud_run_example  = var.create_cloud_run_example
  create_jfrog_docker_repos = var.create_cloud_run_example && var.create_jfrog_docker_repos

  jfrog_docker_local_key   = var.jfrog_docker_local_key
  jfrog_docker_remote_key  = var.jfrog_docker_remote_key
  jfrog_docker_virtual_key = var.jfrog_docker_virtual_key

  # Matches docs/manual-setup.md upstream URL for the connector.
  jfrog_connector_upstream_url = "https://${var.jfrog_host}/${local.jfrog_docker_virtual_key}"

  connector_image = (
    "${var.region}-docker.pkg.dev/${var.project_id}/${var.connector_repository_id}/${var.cloud_run_image_name}:${var.cloud_run_image_tag}"
  )

  secret_latest_version = "${google_secret_manager_secret.jfrog_token.id}/versions/latest"
}

# Block Artifact Registry connector creation until versions/latest is a real token
# (not the bootstrap placeholder). Exits immediately when already rotated. Prints
# reason + time left while waiting for Secret Manager's first SECRET_ROTATE.
resource "null_resource" "wait_for_first_rotation" {
  count = local.create_cloud_run_example ? 1 : 0

  # Stable triggers so later applies do not re-sleep. Re-create (terraform taint /
  # replace) if you need to re-run the wait intentionally.
  triggers = {
    secret_id   = google_secret_manager_secret.jfrog_token.id
    function_id = google_cloudfunctions2_function.rotator.id
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash"]
    command     = "${path.module}/scripts/wait_for_first_rotation.sh"

    environment = {
      PROJECT_ID        = var.project_id
      SECRET_NAME       = var.secret_name
      PLACEHOLDER       = "dummy-token"
      WAIT_SEC          = "360"
      POLL_INTERVAL_SEC = "15"
      POLL_TIMEOUT_SEC  = "300"
    }
  }

  depends_on = [
    google_cloudfunctions2_function.rotator,
    google_cloud_run_v2_service_iam_member.pubsub_invoker,
    google_cloud_run_v2_service_iam_member.eventarc_invoker,
    google_service_account_iam_member.pubsub_token_creator,
    google_secret_manager_secret_version.bootstrap,
    platform_oidc_identity_mapping.rotator,
  ]
}

resource "artifactory_local_docker_v2_repository" "connector" {
  count = local.create_jfrog_docker_repos ? 1 : 0

  key         = local.jfrog_docker_local_key
  description = "Local Docker repo for Artifact Registry connector example"
}

resource "artifactory_remote_docker_repository" "connector" {
  count = local.create_jfrog_docker_repos ? 1 : 0

  key                            = local.jfrog_docker_remote_key
  description                    = "Docker Hub remote for Artifact Registry connector example"
  url                            = "https://registry-1.docker.io/"
  enable_token_authentication    = true
  external_dependencies_enabled  = true
  external_dependencies_patterns = ["**/registry-1.docker.io/**"]
}

resource "artifactory_virtual_docker_repository" "connector" {
  count = local.create_jfrog_docker_repos ? 1 : 0

  key         = local.jfrog_docker_virtual_key
  description = "Virtual Docker repo for Artifact Registry connector example"
  repositories = [
    artifactory_local_docker_v2_repository.connector[0].key,
    artifactory_remote_docker_repository.connector[0].key,
  ]
  default_deployment_repo = artifactory_local_docker_v2_repository.connector[0].key
}

resource "google_artifact_registry_repository" "jfrog_connector" {
  count = local.create_cloud_run_example ? 1 : 0

  project       = var.project_id
  location      = var.region
  repository_id = var.connector_repository_id
  description   = "Connector to JFrog ${local.jfrog_docker_virtual_key}"
  format        = "DOCKER"
  mode          = "REMOTE_REPOSITORY"

  remote_repository_config {
    description                 = "JFrog Docker virtual connector (no cache)"
    disable_upstream_validation = true

    docker_repository {
      custom_repository {
        uri = local.jfrog_connector_upstream_url
      }
    }

    upstream_credentials {
      username_password_credentials {
        username                = var.jfrog_user
        password_secret_version = local.secret_latest_version
      }
    }

    # REMOTE_REPOSITORY + no_cache = Artifact Registry connector repository.
    # https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/artifact_registry_repository
    no_cache {}
  }

  depends_on = [
    google_project_service.required,
    google_secret_manager_secret_version.bootstrap,
    google_secret_manager_secret_iam_member.artifact_registry_accessor,
    artifactory_virtual_docker_repository.connector,
    null_resource.wait_for_first_rotation,
  ]
}

resource "google_cloud_run_v2_service" "nginx_example" {
  count = local.create_cloud_run_example ? 1 : 0

  name     = var.cloud_run_service_name
  project  = var.project_id
  location = var.region

  deletion_protection = false
  ingress             = "INGRESS_TRAFFIC_ALL"

  template {
    containers {
      image = local.connector_image

      ports {
        container_port = 80
      }
    }
  }

  depends_on = [
    google_artifact_registry_repository.jfrog_connector,
  ]
}

resource "google_cloud_run_v2_service_iam_member" "nginx_public" {
  count = local.create_cloud_run_example ? 1 : 0

  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.nginx_example[0].name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# (c) JFrog Ltd. (2026)

terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source = "hashicorp/google"
      # 7.43.0+ required for remote_repository_config.no_cache (connector mode)
      version = "7.43.0"
    }
    google-beta = {
      source = "hashicorp/google-beta"
      # google-beta 7.43.0 not published yet; 7.42.0 is sufficient for resources used here
      version = "7.42.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "2.8.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.9.0"
    }
    platform = {
      source  = "jfrog/platform"
      version = "2.2.10"
    }
    artifactory = {
      source  = "jfrog/artifactory"
      version = "12.11.9"
    }
    null = {
      source  = "hashicorp/null"
      version = "3.2.4"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

provider "platform" {
  url          = "https://${var.jfrog_host}"
  access_token = var.jfrog_access_token
}

provider "artifactory" {
  url          = "https://${var.jfrog_host}/artifactory"
  access_token = var.jfrog_access_token
}

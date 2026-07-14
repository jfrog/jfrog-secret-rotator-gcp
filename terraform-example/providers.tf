terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "5.21.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "5.21.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "2.4.2"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.5.1"
    }
    platform = {
      source  = "jfrog/platform"
      version = "2.2.0"
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

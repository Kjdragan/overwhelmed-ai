terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.32"
    }
  }
}

# Fetch the current project metadata (including number)
data "google_project" "current" {}

provider "google" {
  project = var.project_id
  region  = "us-central1"
}

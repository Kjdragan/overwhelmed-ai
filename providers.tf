terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.32"
    }
  }
}

# ──────────────────────────────────────────────────────────────────────────────

provider "google" {
  project = var.project_id
  region  = "us-central1"
}

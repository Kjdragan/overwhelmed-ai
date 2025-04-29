terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.32"   # lock to the same major version you saw in the log
    }
  }
}

provider "google" {
  project = var.project_id      # ← this is the missing piece
  region  = "us-central1"       # default for Cloud Functions v2 / Scheduler
}

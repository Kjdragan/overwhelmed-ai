terraform {
  backend "gcs" {
    bucket = "overwhelmed2-tf-state-prod"
    prefix = "prod"
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# Fetch the current project info (so we can pass the numeric project number
# into our module for binding the Compute default service account)
data "google_project" "current" {}

# ──────────────────────────────────────────────────────────────────────────────
resource "google_service_account" "yt_ingest_sa" {
  account_id   = "yt-ingest"
  display_name = "yt_ingest Cloud Function runtime"
}

# give the function SA write access to the transcript bucket
resource "google_project_iam_member" "transcript_writer" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.yt_ingest_sa.email}"
}

module "yt_ingest" {
  source         = "./modules/yt_ingest"
  project_id     = var.project_id
  project_number = data.google_project.current.number
  func_sa_email  = google_service_account.yt_ingest_sa.email
}

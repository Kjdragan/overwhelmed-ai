terraform {
  backend "gcs" {
    bucket = "overwhelmed2-tf-state-prod"
    prefix = "prod"
  }
}

# ------------------------------------------------------------------------------
# Use the project number directly instead of fetching it dynamically
# project_number = 321816670619

# ------------------------------------------------------------------------------
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
  project_number = 321816670619
  func_sa_email  = google_service_account.yt_ingest_sa.email
}

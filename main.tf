terraform {
  backend "gcs" {
    bucket = "overwhelmed-tf-state-457816"   # ← new bucket
    prefix = "prod"
  }
}

resource "google_service_account" "yt_ingest_sa" {
  account_id   = "yt-ingest"
  display_name = "yt_ingest Cloud Function runtime"
}

# give runtime SA write access to transcript bucket
resource "google_project_iam_member" "transcript_writer" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.yt_ingest_sa.email}"
}

module "yt_ingest" {
  source        = "./modules/yt_ingest"
  project_id    = var.project_id
  func_sa_email = google_service_account.yt_ingest_sa.email
}

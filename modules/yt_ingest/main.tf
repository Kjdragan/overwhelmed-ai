# modules/yt_ingest/main.tf
resource "google_storage_bucket" "transcripts" {
  name          = "yt-transcripts-${var.project_id}"
  location      = "us-central1"
  force_destroy = true
  uniform_bucket_level_access = true
}

data "archive_file" "src_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../functions/yt_ingest"
  output_path = "${path.module}/src.zip"
}

resource "google_storage_bucket_object" "src_upload" {
  name   = "yt_ingest_src_${data.archive_file.src_zip.output_md5}.zip"
  bucket = google_storage_bucket.transcripts.name
  source = data.archive_file.src_zip.output_path
}

resource "google_cloudfunctions2_function" "yt_ingest" {
  name     = "yt_ingest"
  location = "us-central1"

  build_config {
    runtime     = "python312"
    entry_point = "ingest"
    source {
      storage_source {
        bucket = google_storage_bucket.transcripts.name
        object = google_storage_bucket_object.src_upload.name
      }
    }
  }

  service_config {
    max_instance_count   = 1
    available_memory     = "256M"
    timeout_seconds      = 60
    service_account_email = var.func_sa_email
    environment_variables = {
      TRANSCRIPT_BUCKET = google_storage_bucket.transcripts.name
    }
  }
}

resource "google_cloud_scheduler_job" "yt_ingest_twice_daily" {
  name        = "yt-ingest-twice-daily"
  description = "Pull new AI transcripts twice per day"
  schedule    = "0 9,21 * * *"
  time_zone   = "America/Chicago"

  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions2_function.yt_ingest.service_config[0].uri
    oidc_token {
      service_account_email = var.func_sa_email
    }
  }
}

resource "google_service_account_iam_member" "ci_act_as_default_compute" {
  service_account_id = "projects/${data.google_project.current.number}/serviceAccounts/${data.google_project.current.number}-compute@developer.gserviceaccount.com"
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:overwhelmed-ci@${var.project_id}.iam.gserviceaccount.com"
}

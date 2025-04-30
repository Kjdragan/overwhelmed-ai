terraform {
  backend "gcs" {
    bucket = "overwhelmed2-tf-state-prod"
    prefix = "prod"
  }
}

provider "google" {
  project = var.project_id
  region  = "us-central1"
}

# Just create a simple storage bucket to test the deployment
resource "google_storage_bucket" "test_bucket" {
  name          = "overwhelmed2-test-bucket"
  location      = "US"
  force_destroy = true
  
  uniform_bucket_level_access = true
}

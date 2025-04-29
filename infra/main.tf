provider "google" {
  project = "kev-agent-engine"
  region  = "us-central1"
}

resource "google_storage_bucket" "audio" {
  name     = "kev-terraform-overwhelmed-audio"
  location = "US"
  force_destroy = true
  
  # Add uniform bucket level access
  uniform_bucket_level_access = true
}

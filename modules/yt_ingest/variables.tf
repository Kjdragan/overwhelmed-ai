# /modules/yt_ingest/variables.tf - Variables for YouTube Ingestion module

variable "project_id" {
  type = string
}

variable "project_number" {
  description = "Numeric GCP project number for default compute SA"
  type        = number
}

variable "func_sa_email" {
  type = string
}

# Terraform CI/CD Process for overwhelmed2

_A hands-on reference for wiring GitHub → Cloud Build → Terraform on GCP_

---

## 1 Overview: what we built

| Layer                     | Purpose                                                 | Key resources                                           |
| ------------------------- | ------------------------------------------------------- | ------------------------------------------------------- |
| **GitHub repo**           | Stores Terraform code and CI config (`cloudbuild.yaml`) | Branch: `main`                                          |
| **Cloud Build trigger**   | Auto-runs on every push to `main`                       | Trigger: **overwhelmed2** (2-gen, region `us-central1`) |
| **User-managed build SA** | Limits blast radius vs. default SA                      | `overwhelmed-ci@overwhelmed2.iam.gserviceaccount.com`   |
| **State bucket**          | Versioned, project-owned, single-region                 | `gs://overwhelmed2-tf-state-prod`                       |
| **Cloud Logging only**    | Stores build logs (no buckets needed)                   | `options.logging: CLOUD_LOGGING_ONLY`                   |

Outcome: a **green end-to-end pipeline**—every commit to `main` triggers a
Terraform plan/apply with state stored safely in GCS and logs in Cloud Logging.

---

## 2 Step-by-step recap

1. **Repository structure**

```
overwhelmed2/
├─ cloudbuild.yaml          # Cloud Build configuration
├─ simple-tf/               # Simplified Terraform for test deployment
│  ├─ main.tf               # Simple resource definitions
│  ├─ variables.tf          # Project variable definitions
│  └─ terraform.tfvars      # Variable values (project_id="overwhelmed2")
├─ functions/               # Cloud Function source code
│  └─ yt_ingest/            # YouTube transcript ingestion function
│     ├─ main.py            # Function entry point
│     └─ requirements.txt   # Python dependencies
└─ modules/                 # Terraform modules
   └─ yt_ingest/            # Module for deploying yt_ingest function
      ├─ main.tf            # Resource definitions
      └─ variables.tf       # Module variables
```

2. **Trigger creation (GitHub → Cloud Build)**

- 2-gen trigger (`gcloud builds triggers create github`)
- Connected to your GitHub repository
- Pointed at custom SA + **Cloud Logging only** policy
- Trigger automatically applies the Terraform in simple-tf/

3. **Custom build service-account**

```bash
# If not already created:
gcloud iam service-accounts create overwhelmed-ci \
  --project=overwhelmed2 \
  --display-name="Cloud Build Service Account"

# Grant required roles:
gcloud projects add-iam-policy-binding overwhelmed2 \
  --member="serviceAccount:overwhelmed-ci@overwhelmed2.iam.gserviceaccount.com" \
  --role=roles/cloudfunctions.developer

gcloud projects add-iam-policy-binding overwhelmed2 \
  --member="serviceAccount:overwhelmed-ci@overwhelmed2.iam.gserviceaccount.com" \
  --role=roles/run.admin

gcloud projects add-iam-policy-binding overwhelmed2 \
  --member="serviceAccount:overwhelmed-ci@overwhelmed2.iam.gserviceaccount.com" \
  --role=roles/logging.logWriter

# Grant access to the state bucket
gsutil iam ch \
  "serviceAccount:overwhelmed-ci@overwhelmed2.iam.gserviceaccount.com:objectAdmin" \
  gs://overwhelmed2-tf-state-prod
```

4. **Terraform backend**
   ```hcl
   terraform {
     backend "gcs" {
       bucket = "overwhelmed2-tf-state-prod"
       prefix = "prod"
     }
   }
   ```
   _State bucket should be created with versioning & UBLE:_
   ```bash
   # Already created, but for reference:
   gsutil mb -l us-central1 -b on gs://overwhelmed2-tf-state-prod
   gsutil versioning set on gs://overwhelmed2-tf-state-prod
   ```

5. **cloudbuild.yaml**
   ```yaml
   options:
     logging: CLOUD_LOGGING_ONLY

   steps:
     - id: Terraform Init & Apply
       name: hashicorp/terraform:1.7
       entrypoint: sh
       args:
         - -c
         - |
             cd simple-tf
             terraform init -input=false -reconfigure
             terraform apply -auto-approve -input=false
   timeout: "1200s"
   ```

---

## 3 Cheat-sheet commands

| Task                      | Command                                                                                                                                                            |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Grant Logs Writer**     | `gcloud projects add-iam-policy-binding overwhelmed2 --member="serviceAccount:overwhelmed-ci@overwhelmed2.iam.gserviceaccount.com" --role=roles/logging.logWriter` |
| **Grant bucket R/W**      | `gsutil iam ch "serviceAccount:overwhelmed-ci@overwhelmed2.iam.gserviceaccount.com:objectAdmin" gs://overwhelmed2-tf-state-prod`                                   |
| **Empty commit**          | `git commit --allow-empty -m "trigger build" && git push`                                                                                                          |
| **Rebase then push**      | `git pull --rebase origin main` → resolve → `git push`                                                                                                             |
| **List build history**    | Console → _Cloud Build ▸ History_ (region)                                                                                                                         |
| **Tail latest log (CLI)** | `gcloud builds log --stream $(gcloud builds list --limit=1 --format='value(id)')`                                                                                  |

---

## 4 Lessons learned & gotchas

| Pain point                                                | Root cause                                    | How we fixed it / tip                                               |
| --------------------------------------------------------- | --------------------------------------------- | ------------------------------------------------------------------- |
| **Log-policy error** (`build.service_account specified…`) | Trigger used a user SA but no log destination | Set `options.logging: CLOUD_LOGGING_ONLY` **or** add `logsBucket`   |
| **403 storage.objects.list**                              | Build SA lacked access to state bucket        | `objectAdmin` on bucket **only** (UBLE ignores project-level roles) |
| **409 bucket exists**                                     | GCS bucket names are global                   | Append project ID or random suffix for uniqueness                   |
| **Terraform stuck on old backend**                        | `terraform init` without `-reconfigure`       | Always add `-reconfigure` when backend block changes                |
| **Push rejected (`fetch first`)**                         | Remote branch ahead of local                  | `git pull --rebase origin main` before pushing                      |
| **Console "you don't have permission to view logs"**      | User lacked `roles/logging.viewer`            | Grant minimal viewer role to human accounts                         |

---

## 5 Moving from simple-tf to main project

Now that you have a working CI/CD pipeline with the simple-tf directory, you can
enhance it to deploy your main project resources:

1. **Update cloudbuild.yaml**
   ```yaml
   options:
     logging: CLOUD_LOGGING_ONLY

   steps:
     - id: Terraform Init & Apply
       name: hashicorp/terraform:1.7
       entrypoint: sh
       args:
         - -c
         - |
             terraform init -input=false -reconfigure
             terraform apply -auto-approve -input=false
   timeout: "1200s"
   ```

2. **Update main.tf** to ensure it has the correct state bucket:
   ```hcl
   terraform {
     backend "gcs" {
       bucket = "overwhelmed2-tf-state-prod"
       prefix = "prod"
     }
   }
   ```

3. **Update project_id** in terraform.tfvars:
   ```hcl
   project_id = "overwhelmed2"
   ```

4. **Create/Update Service Account** for the YouTube ingestion function:
   ```hcl
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
   ```

5. **Add module call** in main.tf:
   ```hcl
   module "yt_ingest" {
     source         = "./modules/yt_ingest"
     project_id     = var.project_id
     project_number = "YOUR_PROJECT_NUMBER" # Replace with your project number
     func_sa_email  = google_service_account.yt_ingest_sa.email
   }
   ```

6. **Commit & push** to deploy the full project:
   ```bash
   git add .
   git commit -m "Deploy full yt_ingest module"
   git push
   ```

7. **Verify deployment** in the Cloud Console:
   - Check Cloud Functions (2nd gen) for the yt_ingest function
   - Check Cloud Scheduler for the yt-ingest-twice-daily job
   - Check Cloud Storage for the yt-transcripts bucket

---

## 6 Testing the YouTube ingestion function

Once deployed, you can test the YouTube ingestion function manually:

```bash
# Get the function URL
FUNCTION_URL=$(gcloud functions describe yt_ingest --gen2 --region us-central1 --format='value(serviceConfig.uri)')

# Generate an auth token
TOKEN=$(gcloud auth print-identity-token)

# Test with a sample YouTube video
curl -X POST "$FUNCTION_URL" \
     -H "Authorization: Bearer $TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"url":"https://www.youtube.com/watch?v=dQw4w9WgXcQ"}'
```

The function should return:

- "ok" (HTTP 200) if successful
- "no English transcript available" (HTTP 204) if no transcript exists
- An error message (HTTP 502) if the video cannot be accessed

You can verify that JSON files are being created in the yt-transcripts bucket
with the YouTube video IDs as filenames.

---

## 7 Next steps

1. **Enhance the yt_ingest function** to process the transcripts and store them
   in a more queryable format
2. **Add additional Cloud Functions** for processing the transcripts
3. **Set up a Pub/Sub topic** for asynchronous processing
4. **Create a frontend** for searching and displaying the processed transcripts
5. **Integrate with AI/ML services** for analysis or generation tasks

---

> Remember: Your Terraform pipeline is now set up to deploy all of these future
> enhancements automatically when you push to the main branch!

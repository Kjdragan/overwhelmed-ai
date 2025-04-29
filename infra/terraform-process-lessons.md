```markdown
# terraform-process-lessons.md

_A hands-on reference for wiring GitHub → Cloud Build → Terraform on GCP_

---

## 1 Overview: what we built

| Layer                     | Purpose                                                             | Key resources                                          |
| ------------------------- | ------------------------------------------------------------------- | ------------------------------------------------------ |
| **GitHub repo**           | Stores Terraform code (`main.tf`) and CI config (`cloudbuild.yaml`) | Branch: `main`                                         |
| **Cloud Build trigger**   | Auto-runs on every push to `main`                                   | Trigger: **overwhelmed** (2-gen, region `us-central1`) |
| **User-managed build SA** | Limits blast radius vs. default SA                                  | `overwhelmed-ci@…`                                     |
| **State bucket**          | Versioned, project-owned, single-region                             | `gs://overwhelmed-tf-state-457816`                     |
| **Cloud Logging only**    | Stores build logs (no buckets needed)                               | `options.logging: CLOUD_LOGGING_ONLY`                  |

Outcome: a **green end-to-end pipeline**—every commit to `main` triggers a
Terraform plan/apply with state stored safely in GCS and logs in Cloud Logging.

---

## 2 Step-by-step recap

1. **Repository skeleton**
```

overwhelmed-ai/ ├─ cloudbuild.yaml └─ main.tf

````
2. **Trigger creation (GitHub → Cloud Build)**
* 2-gen trigger (`gcloud builds triggers create github … --repository=…`)
* Pointed at custom SA + **Cloud Logging only** policy.

3. **Custom build service-account**
```bash
gcloud iam service-accounts create overwhelmed-ci
# Roles required:
roles/cloudfunctions.developer
roles/run.admin
roles/logging.logWriter
# Bucket-specific:
gsutil iam ch \
  "serviceAccount:overwhelmed-ci@…:objectAdmin" \
  gs://overwhelmed-tf-state-457816
````

4. **Terraform backend**
   ```hcl
   terraform {
     backend "gcs" {
       bucket = "overwhelmed-tf-state-457816"
       prefix = "prod"
     }
   }
   ```
   _Bucket created with versioning & UBLE:_
   ```bash
   gsutil mb -l us-central1 -b on gs://overwhelmed-tf-state-457816
   gsutil versioning set on gs://overwhelmed-tf-state-457816
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
             terraform init -input=false -reconfigure
             terraform apply -auto-approve -input=false
   timeout: "1200s"
   ```

---

## 3 Cheat-sheet commands

| Task                      | Command                                                                                                        |
| ------------------------- | -------------------------------------------------------------------------------------------------------------- |
| **Grant Logs Writer**     | `gcloud projects add-iam-policy-binding $PROJECT --member="serviceAccount:$SA" --role=roles/logging.logWriter` |
| **Grant bucket R/W**      | `gsutil iam ch "serviceAccount:$SA:objectAdmin" gs://$BUCKET`                                                  |
| **Empty commit**          | `git commit --allow-empty -m "trigger build" && git push`                                                      |
| **Rebase then push**      | `git pull --rebase origin main` → resolve → `git push`                                                         |
| **List build history**    | Console → _Cloud Build ▸ History_ (region)                                                                     |
| **Tail latest log (CLI)** | `gcloud builds log --stream $(gcloud builds list --limit=1 --format='value(id)')`                              |

---

## 4 Lessons learned & gotchas

| Pain point                                                | Root cause                                    | How we fixed it / tip                                               |
| --------------------------------------------------------- | --------------------------------------------- | ------------------------------------------------------------------- |
| **Log-policy error** (`build.service_account specified…`) | Trigger used a user SA but no log destination | Set `options.logging: CLOUD_LOGGING_ONLY` **or** add `logsBucket`   |
| **403 storage.objects.list**                              | Build SA lacked access to state bucket        | `objectAdmin` on bucket **only** (UBLE ignores project-level roles) |
| **409 bucket exists**                                     | GCS bucket names are global                   | Append project ID or random suffix for uniqueness                   |
| **Terraform stuck on old backend**                        | `terraform init` without `-reconfigure`       | Always add `-reconfigure` when backend block changes                |
| **Push rejected (`fetch first`)**                         | Remote branch ahead of local                  | `git pull --rebase origin main` before pushing                      |
| **Console “you don’t have permission to view logs”**      | User lacked `roles/logging.viewer`            | Grant minimal viewer role to human accounts                         |

---

## 5 Reusable checklist for next project

1. **Plan names** (repo, trigger, bucket) ⚙️
2. **Create user-managed build SA** → minimal roles + `logWriter`.
3. **Make bucket** (`gsutil mb`) → enable versioning → grant `objectAdmin`.
4. **Write Terraform backend** with that bucket name.
5. **Write `cloudbuild.yaml`** (`init -reconfigure`, `apply`, Cloud Logging).
6. **Create 2-gen trigger** in same region as bucket.
7. **Grant yourself `logging.viewer`** so you can actually see logs.
8. **Push empty commit** → watch Cloud Build turn green.
9. **Verify** `terraform.tfstate` appears in the bucket.
10. Start adding real Terraform resources & let the pipeline deploy them.

---

## 6 What we achieved

- **Fully automated IaC deployment loop** on every push.
- **Least-privilege** build identity & bucket-level IAM.
- **No hidden buckets** – logs in Cloud Logging, state in a single-region
  bucket.
- **One-command recovery**: delete bucket contents or roll back via
  object-versioning.
- Foundation on which we can layer functions, schedulers, Pub/Sub, etc.

---

> **Next up** _Add the `yt_ingest` Cloud Function & Cloud Scheduler to start
> populating our knowledge ingest pipeline — the CI/CD path is already in
> place!_

---

## 7  Next up — deploying **yt_ingest** + Scheduler

A minimal, production‑ready pattern you can copy‑paste into the repo.

### 7.1  Repo layout (new files only)

```
overwhelmed-ai/
├─ functions/yt_ingest/            # Cloud Function source
│  ├─ main.py                      # entry‑point
│  └─ requirements.txt             # (google‑cloud‑storage, yt‑dlp, etc.)
└─ modules/
   └─ yt_ingest/
      ├─ main.tf                   # TF resources
      ├─ variables.tf
      └─ outputs.tf
```

### 7.2  Terraform module (modules/yt_ingest/main.tf)

```hcl
resource "google_storage_bucket" "transcripts" {
  name          = "yt-ingest-cache-${var.project_id}"
  location      = "us-central1"
  force_destroy = true
}

resource "google_cloudfunctions2_function" "yt_ingest" {
  name        = "yt_ingest"
  location    = "us-central1"
  build_config {
    runtime     = "python312"
    entry_point = "ingest"
    source {
      storage_source {
        bucket = google_storage_bucket.transcripts.name
        object = google_storage_bucket_object.source_zip.name
      }
    }
  }
  service_config {
    max_instance_count = 1
    available_memory   = "256M"
    service_account_email = var.func_sa_email
  }
}

resource "google_cloud_scheduler_job" "yt_ingest_daily" {
  name             = "yt-ingest-daily"
  description      = "Download new transcripts twice per day"
  schedule         = "0 9,21 * * *"   # 09:00 & 21:00 Chicago
  time_zone        = "America/Chicago"
  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions2_function.yt_ingest.service_config[0].uri
    oidc_token {
      service_account_email = var.func_sa_email
    }
  }
}
```

_Variables:_ `project_id`, `func_sa_email`

### 7.3  Function code (functions/yt_ingest/main.py)

```python
import base64, json, os, tempfile, yt_dlp, google.cloud.storage as gcs

def ingest(request):
    """Cloud Function entry‑point – triggered by Scheduler (HTTP)."""
    body = request.get_json(silent=True) or {}
    url  = body.get("url", "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    tmp  = tempfile.mkdtemp()
    ydl  = yt_dlp.YoutubeDL({"outtmpl": f"{tmp}/%(id)s.%(ext)s", "skip_download": True})
    info = ydl.extract_info(url, download=False)
    transcript = info.get("automatic_captions", {}).get("en", [{}])[0].get("url")
    if not transcript:
        return ("no transcript", 204)
    # upload to GCS bucket
    bucket = gcs.Client().bucket(os.environ["TRANSCRIPT_BUCKET"])
    blob   = bucket.blob(f"{info["id"]}.json")
    blob.upload_from_string(json.dumps(info), content_type="application/json")
    return ("ok", 200)
```

_(Set `TRANSCRIPT_BUCKET` env‑var in `google_cloudfunctions2_function`.)_

### 7.4  IAM roles for the function SA

- `roles/storage.objectAdmin` on the transcript bucket
- (optional) `roles/cloudscheduler.jobRunner` if using Pub/Sub trigger later

### 7.5  Wire into the pipeline

1. **Add module call** to root `main.tf`:
   ```hcl
   module "yt_ingest" {
     source         = "./modules/yt_ingest"
     project_id     = var.project_id
     func_sa_email  = google_service_account.func_sa.email
   }
   ```
2. **Commit & push** → Cloud Build applies Terraform → Function + Scheduler
   deploy.
3. **Validate** in console: Cloud Functions (2nd gen) list & Scheduler job list.

### 7.6  Local quick‑test

```bash
curl -X POST "$(gcloud functions describe yt_ingest --gen2 --region us-central1 --format='value(serviceConfig.uri)')" \
     -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
     -H "Content-Type: application/json" \
     -d '{"url":"https://www.youtube.com/watch?v=dQw4w9WgXcQ"}'
```

---

_Clone, adjust names, push — the Terraform/Cloud Build stack you just built will
deploy every resource above automatically._

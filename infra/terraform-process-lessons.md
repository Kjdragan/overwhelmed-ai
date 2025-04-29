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

```
```

# /functions/yt_ingest/main.py - YouTube ingestion Cloud Function

# functions/yt_ingest/main.py
import json
import os
import tempfile

import yt_dlp
from yt_dlp.utils import DownloadError
from google.cloud import storage


def ingest(request):
    """HTTP entry-point – returns 200/204/502 so Scheduler stays happy."""
    body = request.get_json(silent=True) or {}
    url = body.get("url", "https://www.youtube.com/watch?v=dQw4w9WgXcQ")

    tmp_dir = tempfile.mkdtemp()
    ydl = yt_dlp.YoutubeDL({
        "outtmpl": f"{tmp_dir}/%(id)s.%(ext)s",
        "skip_download": True
    })

    try:
        info = ydl.extract_info(url, download=False)
    except DownloadError as e:
        # strip the leading "ERROR: " if present
        msg = e.args[0].removeprefix("ERROR: ")
        return (f"could not fetch captions: {msg}", 502)

    transcript_url = (
        info
        .get("automatic_captions", {})
        .get("en", [{}])[0]
        .get("url")
    )
    if not transcript_url:
        return ("no English transcript available", 204)

    # upload full metadata (including captions URL) to GCS
    bucket_name = os.environ["TRANSCRIPT_BUCKET"]
    client = storage.Client()
    bucket = client.bucket(bucket_name)
    blob = bucket.blob(f"{info['id']}.json")
    blob.upload_from_string(
        json.dumps(info),
        content_type="application/json"
    )

    return ("ok", 200)

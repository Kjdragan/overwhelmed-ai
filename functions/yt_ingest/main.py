# /functions/yt_ingest/main.py
import json
import os
import tempfile
import io
import sys

import yt_dlp
from yt_dlp.utils import DownloadError
from google.cloud import storage


def ingest(request):
    """HTTP entry-point – returns 200/204/502 so Scheduler stays happy."""
    body = request.get_json(silent=True) or {}
    url = body.get("url", "https://www.youtube.com/watch?v=dQw4w9WgXcQ")

    tmp_dir = tempfile.mkdtemp()

    # Suppress stdout/stderr to prevent yt-dlp output issues
    old_stdout, old_stderr = sys.stdout, sys.stderr
    sys.stdout = io.StringIO()
    sys.stderr = io.StringIO()

    try:
        ydl_opts = {
            "outtmpl": f"{tmp_dir}/%(id)s.%(ext)s",
            "skip_download": True,
            "quiet": True,  # Suppress console output
            "no_warnings": True,  # Suppress warnings
        }

        ydl = yt_dlp.YoutubeDL(ydl_opts)
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
    finally:
        # Restore stdout/stderr
        sys.stdout, sys.stderr = old_stdout, old_stderr

# functions/yt_ingest/main.py
import json, os, tempfile
import yt_dlp
from google.cloud import storage

def ingest(request):
    """HTTP entry-point – returns 200 even if no transcript so Scheduler stays green."""
    body = request.get_json(silent=True) or {}
    url  = body.get("url", "https://www.youtube.com/watch?v=dQw4w9WgXcQ")

    tmp_dir = tempfile.mkdtemp()
    ydl     = yt_dlp.YoutubeDL({"outtmpl": f"{tmp_dir}/%(id)s.%(ext)s", "skip_download": True})
    info    = ydl.extract_info(url, download=False)

    transcript_url = info.get("automatic_captions", {}).get("en", [{}])[0].get("url")
    if not transcript_url:
        return ("no English transcript", 204)

    bucket = storage.Client().bucket(os.environ["TRANSCRIPT_BUCKET"])
    blob   = bucket.blob(f"{info['id']}.json")
    blob.upload_from_string(json.dumps(info), content_type="application/json")

    return ("ok", 200)

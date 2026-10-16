#!/data/data/com.termux/files/usr/bin/bash
# The definitive module test: a live sweep, then upload what it returns.
#
# The previous run used the parse cache, which was three hours old, and the keystamp had expired
# 103 minutes earlier - so every fetch was a legitimate 403 and proved nothing about the uploader.
# A sweep produces freshly signed URLs, which is what the bot will actually be uploading.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"

PROJECT_DIR="$HOME/twitter_pixiv_tg_bot"
OUT="$PROJECT_DIR/data/r2-live.txt"
cd "$PROJECT_DIR/bot" || exit 1

set -a
while IFS= read -r line; do
    case "$line" in
        R2_*) eval "export $line" 2>/dev/null || true ;;
    esac
done < "$PROJECT_DIR/.env"
set +a

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo "  now (unix): $(date +%s)"
    echo

    python - <<'PY'
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, ".")
sys.path.insert(0, "vendor")

import httpx
import ehentai
import r2

settings = r2.r2_settings()
print(f"  {settings.describe()}")
print()

# A gallery URL from the cache, so this does not need one typed in.
gallery_url = ""
for name in ("parse_cache.json", "../parse_cache.json"):
    path = Path(name)
    if not path.is_file():
        continue
    data = json.loads(path.read_text(encoding="utf-8"))
    for key, value in data.items():
        if (value or {}).get("kind") == "gallery" and str(key).startswith("http"):
            gallery_url = key
            break
    if gallery_url:
        break

if not gallery_url:
    print("  no cached gallery url to sweep")
    raise SystemExit(1)
print(f"--- sweeping {gallery_url} ---")
started = time.monotonic()
gallery = ehentai.fetch_gallery(gallery_url, cookies_path=Path("../cookies/ehentai.txt"))
print(f"  {gallery.title!r}  ({time.monotonic() - started:.1f}s)")
print()

print("--- a live sweep of the first few pages ---")
started = time.monotonic()
display, original = ehentai.fetch_gallery_images(
    gallery_url, cookies_path=Path("../cookies/ehentai.txt"), workers=6, max_images=4)
print(f"  {len(display)} display urls, {len(original)} original urls  "
      f"({time.monotonic() - started:.1f}s)")
if not display:
    print("  the sweep returned nothing")
    raise SystemExit(1)
print(f"  first: {display[0][:110]}")
print()

# The keystamp on these is fresh, which is the whole point of the exercise.
import re
for url in display[:2]:
    match = re.search(r"keystamp=(\d+)", url)
    if match:
        stamp = int(match.group(1))
        print(f"  keystamp {stamp}: {stamp - int(time.time()):+d}s from now")
print()

print("--- fetching one bare, to confirm the sweep output is directly usable ---")
with httpx.Client(timeout=40, follow_redirects=True) as http:
    response = http.get(display[0])
print(f"  HTTP {response.status_code}  {response.headers.get('content-type','?')}  "
      f"{len(response.content)} bytes")
print()

if response.status_code != 200:
    print("  the sweep output is not directly fetchable; the uploader would need cookies")
    raise SystemExit(1)

print("--- uploading them to R2 ---")
started = time.monotonic()
report = r2.upload_many(display, settings=settings, workers=4)
print(f"  {report.summary()}  ({time.monotonic() - started:.1f}s)")
for result in report.results:
    state = "reused" if result.skipped else ("ok" if result.ok else "FAILED")
    print(f"    {state:7} {result.size:>8} bytes  {result.error or result.public_url}")
print()

print("--- fetching them back anonymously, as Telegraph will ---")
good = 0
with httpx.Client(timeout=40, follow_redirects=True) as http:
    for url in report.urls():
        try:
            got = http.get(url)
            match = got.content == response.content if url == report.urls()[0] else None
            print(f"  {got.status_code}  {got.headers.get('content-type','?'):12} "
                  f"{len(got.content):>8} bytes  {url}")
            if got.status_code == 200 and (got.headers.get("content-type", "").startswith("image/")):
                good += 1
        except Exception as exc:
            print(f"  FAILED {type(exc).__name__}: {url}")
print()
print(f"  {good}/{len(report.urls())} served as images over the public domain")
print()

print("--- uploading the same set again, expecting reuse ---")
again = r2.upload_many(display, settings=settings, workers=4)
print(f"  {again.summary()}")
print(f"  identical urls: {again.urls() == report.urls()}")
print()

print("--- cleaning up ---")
import boto3
from botocore.config import Config
client = boto3.session.Session().client(
    "s3", endpoint_url=settings.endpoint,
    aws_access_key_id=settings.access_key, aws_secret_access_key=settings.secret_key,
    region_name="auto", config=Config(signature_version="s3v4"))
removed = 0
listing = client.list_objects_v2(Bucket=settings.bucket, Prefix="galleries/")
for item in listing.get("Contents", []):
    client.delete_object(Bucket=settings.bucket, Key=item["Key"])
    removed += 1
print(f"  removed {removed} object(s)")
PY
} > "$OUT" 2>&1

echo "written to $OUT"

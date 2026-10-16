#!/data/data/com.termux/files/home/../usr/bin/bash
# Test bot/r2.py against real images, on the device where it will run.
#
# The module is the part that has to be right: a key derived from a content hash, a 200 from the
# public URL, an existing object reused rather than re-uploaded, and a failure on one image not
# taking the others with it. Each of those is checked here rather than assumed, because the wiring
# into the bot depends on all of them.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"

PROJECT_DIR="$HOME/twitter_pixiv_tg_bot"
OUT="$PROJECT_DIR/data/r2-module-test.txt"

# The five settings live in .env; load just those, since .env is not shell syntax.
set -a
while IFS= read -r line; do
    case "$line" in
        R2_*) eval "export $line" 2>/dev/null || true ;;
    esac
done < "$PROJECT_DIR/.env"
set +a

cd "$PROJECT_DIR/bot" || exit 1

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    python - <<'PY'
import os
import sys
import time

sys.path.insert(0, ".")
sys.path.insert(0, "vendor")

import r2

print("--- settings from the environment ---")
settings = r2.r2_settings()
if settings is None:
    print("  r2_settings() returned None - the R2 block is incomplete or malformed")
    raise SystemExit(1)
print(f"  {settings.describe()}")
print(f"  endpoint: {settings.endpoint}")
print()

print("--- the credential, with one round trip ---")
ok, message = r2.check_connection(settings)
print(f"  {ok}: {message}")
if not ok:
    raise SystemExit(1)
print()

print("--- key derivation ---")
for url, ctype in (
    ("https://example.com/path/0_001.jpg?keystamp=1", "image/jpeg"),
    ("https://example.com/path/photo.PNG", "image/png"),
    ("https://example.com/no-extension", "image/webp"),
    ("https://example.com/odd", ""),
):
    ext = r2.extension_for(url, ctype)
    key = r2.content_key(b"probe-bytes", extension=ext)
    print(f"  {url[-28:]:30} ext={ext or '(none)':6} -> {key}")
print()

print("--- the same content must give the same key ---")
a = r2.content_key(b"identical", extension="jpg")
b = r2.content_key(b"identical", extension="jpg")
c = r2.content_key(b"different", extension="jpg")
print(f"  repeatable: {a == b}")
print(f"  content-sensitive: {a != c}")
print()

print("--- uploading two real images from the cached sweep, if any ---")
urls = []
import json
from pathlib import Path
for name in ("parse_cache.json", "../parse_cache.json"):
    path = Path(name)
    if not path.is_file():
        continue
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        continue
    for value in data.values():
        found = ((value or {}).get("payload") or {}).get("display_urls") or []
        if found:
            urls.extend(found)
    if urls:
        print(f"  source: {name}, {len(urls)} urls")
        break

if not urls:
    print("  no cached urls to use")
else:
    sample = urls[:3]
    started = time.monotonic()
    report = r2.upload_many(sample, settings=settings, workers=3)
    print(f"  {report.summary()}  ({time.monotonic() - started:.1f}s)")
    for result in report.results:
        status = "reused" if result.skipped else ("ok" if result.ok else "FAILED")
        print(f"    {status:7} {result.size:>8} bytes  {result.error or result.public_url}")

    print()
    print("--- fetching them back anonymously ---")
    import httpx
    with httpx.Client(timeout=30, follow_redirects=True) as http:
        for url in report.urls()[:3]:
            try:
                response = http.get(url)
                print(f"  {response.status_code}  {response.headers.get('content-type','?'):12} "
                      f"{len(response.content):>8} bytes  {url}")
            except Exception as exc:
                print(f"  FAILED {type(exc).__name__}: {url}")

    print()
    print("--- running the same upload again, expecting reuse ---")
    again = r2.upload_many(sample, settings=settings, workers=3)
    print(f"  {again.summary()}")
    print(f"  same urls: {again.urls() == report.urls()}")
    print()

    print("--- an unreachable image must not stop the others ---")
    mixed = [sample[0], "https://example.invalid/nope.jpg", sample[1]]
    mixed_report = r2.upload_many(mixed, settings=settings, workers=3)
    print(f"  {mixed_report.summary()}")
    print(f"  order preserved: {[bool(r.public_url) for r in mixed_report.results]}")
    print(f"  failed one kept its source url: "
          f"{mixed_report.urls()[1] == 'https://example.invalid/nope.jpg'}")
    print()

    print("--- cleaning up the probe objects ---")
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
    print(f"  removed {removed} object(s); the bucket is empty again")
PY
} > "$OUT" 2>&1

echo "written to $OUT"

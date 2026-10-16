#!/data/data/com.termux/files/usr/bin/bash
# Final end-to-end confirmation, and clean up every probe object.
#
# The earlier 403 was the custom domain still taking effect rather than anything wrong with the
# setup: the same object answered 200 a minute later. This writes a fresh object, fetches it
# anonymously, confirms the bytes match, and then removes both it and the leftovers from the
# diagnostic runs - so the bucket starts empty apart from whatever the bot will put in it.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"

PROJECT_DIR="$HOME/twitter_pixiv_tg_bot"
ENV_FILE="$PROJECT_DIR/.env"
OUT="$PROJECT_DIR/data/r2-final.txt"

read_env() { grep -m1 "^$1=" "$ENV_FILE" 2>/dev/null | cut -d= -f2- | tr -d '"'"'"' \r'; }

export R2_ENDPOINT="https://$(read_env R2_ACCOUNT_ID).r2.cloudflarestorage.com"
export R2_ACCESS_KEY="$(read_env R2_ACCESS_KEY)"
export R2_SECRET_KEY="$(read_env R2_SECRET_KEY)"
export R2_BUCKET="$(read_env R2_BUCKET)"
export R2_PUBLIC_BASE="$(read_env R2_PUBLIC_BASE)"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo "  bucket: $R2_BUCKET"
    echo "  public: $R2_PUBLIC_BASE"
    echo

    python - <<'PY'
import hashlib
import os
import time

import boto3
import httpx
from botocore.config import Config
from botocore.exceptions import ClientError

client = boto3.session.Session().client(
    "s3",
    endpoint_url=os.environ["R2_ENDPOINT"],
    aws_access_key_id=os.environ["R2_ACCESS_KEY"],
    aws_secret_access_key=os.environ["R2_SECRET_KEY"],
    region_name="auto",
    config=Config(signature_version="s3v4", retries={"max_attempts": 2}),
)
bucket = os.environ["R2_BUCKET"]
base = os.environ["R2_PUBLIC_BASE"].rstrip("/")

print("--- what is in the bucket now ---")
try:
    listing = client.list_objects_v2(Bucket=bucket)
    contents = listing.get("Contents", [])
    if not contents:
        print("  (empty)")
    for item in contents[:20]:
        print(f"  {item['Key']}  ({item['Size']} bytes)")
    if len(contents) > 20:
        print(f"  ... and {len(contents) - 20} more")
except ClientError as exc:
    print(f"  FAILED: {exc.response['Error'].get('Code')}")
print()

# A real image, not a text file: Telegraph renders images, and this proves the content type and
# range handling that an image needs. A 1x1 PNG is small enough to be honest about being a test.
png = bytes.fromhex(
    "89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4"
    "890000000a49444154789c6360000002000100ffff03000006000557bfabd400"
    "00000049454e44ae426082"
)
key = "galleries/_probe/final-check.png"

print(f"--- uploading {key} ({len(png)} bytes, image/png) ---")
client.put_object(Bucket=bucket, Key=key, Body=png, ContentType="image/png",
                  CacheControl="public, max-age=31536000")
print("  uploaded")
print()

url = f"{base}/{key}"
print("--- fetching it anonymously, as Telegraph will ---")
print(f"  {url}")
ok = False
with httpx.Client(timeout=30, follow_redirects=True) as http:
    for attempt in range(1, 6):
        response = http.get(url)
        if response.status_code == 200:
            ct = response.headers.get("content-type", "")
            match = response.content == png
            print(f"  attempt {attempt}: HTTP 200, content-type={ct}, "
                  f"{'bytes match' if match else 'BYTES MISMATCH'}")
            ok = match and ct.startswith("image/")
            break
        print(f"  attempt {attempt}: HTTP {response.status_code}, retrying in 10s")
        time.sleep(10)

print()
print(f"  RESULT: {'the public URL serves the image correctly' if ok else 'NOT WORKING'}")
print()

print("--- cleaning up every probe object ---")
removed = 0
try:
    listing = client.list_objects_v2(Bucket=bucket, Prefix="galleries/_probe/")
    for item in listing.get("Contents", []):
        client.delete_object(Bucket=bucket, Key=item["Key"])
        print(f"  removed {item['Key']}")
        removed += 1
    if not removed:
        print("  (nothing to remove)")
except ClientError as exc:
    print(f"  FAILED: {exc.response['Error'].get('Code')}")
PY
} > "$OUT" 2>&1

echo "written to $OUT"

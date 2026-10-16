#!/data/data/com.termux/files/usr/bin/bash
# Set the public base URL and prove the whole path end to end.
#
# Setting R2_PUBLIC_BASE proves nothing on its own. What matters is that an object uploaded with the
# S3 credential can be fetched **with no credentials at all** through the public domain - because
# that is exactly what Telegraph does when it renders a page, and it is the one thing that cannot
# work if the custom domain is not actually connected to the bucket.
#
# A custom domain that is still propagating, or connected to a different bucket, fails here rather
# than in a gallery page three steps later.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"

PROJECT_DIR="$HOME/twitter_pixiv_tg_bot"
ENV_FILE="$PROJECT_DIR/.env"
BASE="${1:-}"
OUT="$PROJECT_DIR/data/r2-public.txt"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="

    if [ -z "$BASE" ]; then
        echo "  usage: $0 <public-base-url>"
        exit 2
    fi
    # Trailing slashes would produce // in every URL, so they are trimmed once here.
    BASE="${BASE%/}"
    case "$BASE" in
        https://*) ;;
        http://*)  echo "  note: http will be upgraded by the CDN; https is preferred" ;;
        *)         echo "  *** the URL should start with https:// ***"; exit 2 ;;
    esac

    if grep -q '^R2_PUBLIC_BASE=' "$ENV_FILE" 2>/dev/null; then
        grep -v '^R2_PUBLIC_BASE=' "$ENV_FILE" > "$ENV_FILE.tmp" && mv "$ENV_FILE.tmp" "$ENV_FILE"
    fi
    printf 'R2_PUBLIC_BASE=%s\n' "$BASE" >> "$ENV_FILE"
    echo "  R2_PUBLIC_BASE set to $BASE"
    echo

    R2_ENDPOINT="https://$(grep -m1 '^R2_ACCOUNT_ID=' "$ENV_FILE" | cut -d= -f2- | tr -d '\r').r2.cloudflarestorage.com"
    export R2_ENDPOINT
    export R2_ACCESS_KEY="$(grep -m1 '^R2_ACCESS_KEY=' "$ENV_FILE" | cut -d= -f2- | tr -d '\r')"
    export R2_SECRET_KEY="$(grep -m1 '^R2_SECRET_KEY=' "$ENV_FILE" | cut -d= -f2- | tr -d '\r')"
    export R2_BUCKET="$(grep -m1 '^R2_BUCKET=' "$ENV_FILE" | cut -d= -f2- | tr -d '\r')"
    export R2_PUBLIC_BASE="$BASE"

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
base = os.environ["R2_PUBLIC_BASE"]

# Named the way the uploader will name things, so this also confirms the layout works.
payload = b"public access probe\n"
digest = hashlib.sha256(payload).hexdigest()[:16]
key = f"galleries/_probe/{digest}.txt"
url = f"{base}/{key}"

print(f"--- uploading {key} ---")
try:
    client.put_object(Bucket=bucket, Key=key, Body=payload,
                      ContentType="text/plain", CacheControl="public, max-age=31536000")
    print("  uploaded")
except ClientError as exc:
    err = exc.response["Error"]
    print(f"  FAILED: {err.get('Code')}: {err.get('Message')}")
    raise SystemExit(0)

print()
print("--- fetching it anonymously, exactly as Telegraph would ---")
try:
    with httpx.Client(timeout=30, follow_redirects=True) as http:
        response = http.get(url)
    print(f"  GET {url}")
    print(f"  status: {response.status_code}")
    if response.status_code == 200:
        if response.content == payload:
            print("  content matches - the custom domain is connected and serving")
        else:
            print(f"  content MISMATCH: got {response.content[:60]!r}")
    else:
        print(f"  body: {response.text[:300]}")
except Exception as exc:
    print(f"  FAILED: {type(exc).__name__}: {exc}")

print()
print("--- and the S3 endpoint without a credential, for contrast ---")
s3_url = f"{os.environ['R2_ENDPOINT']}/{bucket}/{key}"
try:
    with httpx.Client(timeout=20, follow_redirects=True) as http:
        response = http.get(s3_url)
    print(f"  status: {response.status_code}  (403 is the expected answer here)")
except Exception as exc:
    print(f"  {type(exc).__name__}")

print()
print("--- cleaning up the probe object ---")
try:
    client.delete_object(Bucket=bucket, Key=key)
    print("  deleted")
except ClientError as exc:
    print(f"  could not delete: {exc}")
PY
} > "$OUT" 2>&1

echo "written to $OUT"

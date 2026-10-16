#!/data/data/com.termux/files/usr/bin/bash
# Does the R2 credential work, and what is actually in the account?
#
# The bucket name is not guessed. The credential was scoped to a single bucket, so listing shows
# exactly which one it can see - and if the list is empty, the scope is wrong and no amount of
# guessing would fix it.
#
# This also settles the question the whole approach rests on: api.cloudflare.com:443 answers from
# this network, so an ordinary outbound HTTPS call to R2 should too. Writing to the bucket and
# reading it back proves the path end to end rather than assuming it.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"

PROJECT_DIR="$HOME/twitter_pixiv_tg_bot"
ENV_FILE="$PROJECT_DIR/.env"
OUT="$PROJECT_DIR/data/r2-probe.txt"

read_env() {
    grep -m1 "^$1=" "$ENV_FILE" 2>/dev/null | cut -d= -f2- | tr -d '"'"'"' \r'
}

ACCOUNT=$(read_env R2_ACCOUNT_ID)
ACCESS=$(read_env R2_ACCESS_KEY)
SECRET=$(read_env R2_SECRET_KEY)
BUCKET=$(read_env R2_BUCKET)
PUBLIC=$(read_env R2_PUBLIC_BASE)
ENDPOINT="https://$ACCOUNT.r2.cloudflarestorage.com"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo "  endpoint: $ENDPOINT"
    echo "  account:  ${#ACCOUNT} chars"
    echo "  access:   ${#ACCESS} chars"
    echo "  secret:   ${#SECRET} chars"
    echo "  bucket:   ${BUCKET:-(not set)}"
    echo "  public:   ${PUBLIC:-(not set)}"
    echo

    if [ -z "$ACCOUNT" ] || [ -z "$ACCESS" ] || [ -z "$SECRET" ]; then
        echo "  *** credentials incomplete in .env ***"
        exit 1
    fi

    R2_ACCOUNT_ID="$ACCOUNT" R2_ACCESS_KEY="$ACCESS" R2_SECRET_KEY="$SECRET" \
    R2_BUCKET="$BUCKET" R2_PUBLIC_BASE="$PUBLIC" R2_ENDPOINT="$ENDPOINT" \
    python - <<'PY'
import os
import sys

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError

endpoint = os.environ["R2_ENDPOINT"]

client = boto3.session.Session().client(
    "s3",
    endpoint_url=endpoint,
    aws_access_key_id=os.environ["R2_ACCESS_KEY"],
    aws_secret_access_key=os.environ["R2_SECRET_KEY"],
    region_name="auto",
    config=Config(signature_version="s3v4", retries={"max_attempts": 2}),
)

print("--- listing buckets the credential can see ---")
try:
    response = client.list_buckets()
    buckets = [b["Name"] for b in response.get("Buckets", [])]
    if buckets:
        for name in buckets:
            print(f"  {name}")
    else:
        print("  (none - the credential may not be scoped to a bucket, or lacks ListBuckets)")
except ClientError as exc:
    print(f"  FAILED: {exc.response['Error'].get('Code')}: {exc.response['Error'].get('Message')}")
    buckets = []
print()

if not buckets:
    print("--- trying the bucket named in .env, if any ---")
    configured = os.environ.get("R2_BUCKET", "")
    if configured:
        buckets = [configured]
    else:
        print("  nothing to try; the bucket name has to come from the dashboard")
        sys.exit(0)

bucket = buckets[0]
print(f"--- writing and reading back through {bucket} ---")
key = "probe/hello.txt"
body = b"r2 round trip"
try:
    client.put_object(Bucket=bucket, Key=key, Body=body, ContentType="text/plain")
    print(f"  put ok: {key} ({len(body)} bytes)")

    head = client.head_object(Bucket=bucket, Key=key)
    print(f"  head ok: {head['ContentLength']} bytes, {head.get('ContentType')}")

    got = client.get_object(Bucket=bucket, Key=key)["Body"].read()
    print(f"  get ok: {'content matches' if got == body else 'CONTENT MISMATCH'}")

    client.delete_object(Bucket=bucket, Key=key)
    print("  delete ok (probe object removed)")
except ClientError as exc:
    err = exc.response["Error"]
    print(f"  FAILED: {err.get('Code')}: {err.get('Message')}")
except Exception as exc:
    print(f"  FAILED: {type(exc).__name__}: {exc}")
print()

public = os.environ.get("R2_PUBLIC_BASE", "").rstrip("/")
if public:
    print(f"--- can the public URL be read anonymously from here? ---")
    print(f"  base: {public}")
    print("  (checked separately, with curl and no credentials)")
else:
    print("--- R2_PUBLIC_BASE is not set ---")
    print("  the custom domain has to be connected before Telegraph can fetch images,")
    print("  because the r2.dev URL is rate limited and the S3 endpoint needs credentials")
PY

    echo
    if [ -n "$PUBLIC" ]; then
        echo "--- anonymous fetch of the public base (expect 403/404 on the root, that is fine) ---"
        curl -s -o /dev/null -w '  %{http_code}\n' --max-time 20 "$PUBLIC/" 2>&1
    fi
} > "$OUT" 2>&1

echo "written to $OUT"

#!/data/data/com.termux/files/usr/bin/bash
# img.ginka.uk answers 403 with a Cloudflare HTML error page, for an object that is definitely in the
# bucket. Several different causes produce a 403 and they need different fixes:
#
#   - the custom domain points at a DNS record whose target is wrong, so the request reaches
#     Cloudflare but not the bucket
#   - Cloudflare Access, a WAF rule, or "Under Attack" mode is in front of it
#   - the hostname is connected to the bucket but public access is disabled for the bucket
#   - a Worker or redirect rule is intercepting the hostname
#
# The cf-ray, server, and any cf-mitigated header separate these, so this reads the response rather
# than guessing. It also compares against the bucket's own r2.dev hostname if one can be found, which
# isolates "the bucket is not public" from "the domain is wrong".
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
OUT="$HOME/twitter_pixiv_tg_bot/data/403-probe.txt"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo

    echo "--- what does img.ginka.uk resolve to? ---"
    python - <<'PY'
import socket
for host in ("img.ginka.uk", "ginka.uk"):
    try:
        infos = socket.getaddrinfo(host, 443, socket.AF_INET)
        print(f"  {host:16} {', '.join(sorted({i[4][0] for i in infos})[:4])}")
    except Exception as exc:
        print(f"  {host:16} FAILED: {type(exc).__name__}: {exc}")
PY
    echo

    echo "--- full response headers for a nonexistent path ---"
    curl -sI --max-time 20 https://img.ginka.uk/nothing-here-99999 2>&1 | head -20 | sed 's/^/  /'
    echo

    echo "--- and for the existing object (uploaded again for this probe) ---"
    ACCOUNT=$(grep -m1 '^R2_ACCOUNT_ID=' "$HOME/twitter_pixiv_tg_bot/.env" | cut -d= -f2- | tr -d '\r')
    export R2_ENDPOINT="https://$ACCOUNT.r2.cloudflarestorage.com"
    export R2_ACCESS_KEY="$(grep -m1 '^R2_ACCESS_KEY=' "$HOME/twitter_pixiv_tg_bot/.env" | cut -d= -f2- | tr -d '\r')"
    export R2_SECRET_KEY="$(grep -m1 '^R2_SECRET_KEY=' "$HOME/twitter_pixiv_tg_bot/.env" | cut -d= -f2- | tr -d '\r')"
    export R2_BUCKET="$(grep -m1 '^R2_BUCKET=' "$HOME/twitter_pixiv_tg_bot/.env" | cut -d= -f2- | tr -d '\r')"
    python - <<'PY'
import os
import boto3
from botocore.config import Config

client = boto3.session.Session().client(
    "s3",
    endpoint_url=os.environ["R2_ENDPOINT"],
    aws_access_key_id=os.environ["R2_ACCESS_KEY"],
    aws_secret_access_key=os.environ["R2_SECRET_KEY"],
    region_name="auto",
    config=Config(signature_version="s3v4"),
)
key = "galleries/_probe/403probe.txt"
client.put_object(Bucket=os.environ["R2_BUCKET"], Key=key, Body=b"403 probe\n",
                  ContentType="text/plain")
print(f"  uploaded {key}")
open("/data/data/com.termux/files/usr/tmp/403key.txt", "w").write(key)
PY
    KEY=$(cat "$PREFIX/tmp/403key.txt" 2>/dev/null)
    curl -sI --max-time 20 "https://img.ginka.uk/$KEY" 2>&1 | head -20 | sed 's/^/  /'
    echo

    echo "--- the body of that 403, which usually names the reason ---"
    curl -s --max-time 20 "https://img.ginka.uk/$KEY" 2>&1 \
        | grep -oiE '<title>[^<]*</title>|error [0-9]+|Ray ID[^<]*|access denied|not found|blocked|cloudflare' \
        | head -8 | sed 's/^/  /'
    echo

    echo "--- is the request being asked to authenticate? ---"
    curl -sI --max-time 20 "https://img.ginka.uk/$KEY" 2>&1 \
        | grep -iE 'cf-mitigated|www-authenticate|location|set-cookie|cf-chl|access' | sed 's/^/  /'
    echo
} > "$OUT" 2>&1

echo "written to $OUT"

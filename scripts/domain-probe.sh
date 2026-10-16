#!/data/data/com.termux/files/usr/bin/bash
# ginka.uk answers 404 for an object that is definitely in the bucket, so the domain is not serving
# that bucket. There are several distinct reasons and they need different fixes:
#
#   - the custom domain was never connected to the bucket (the object is there, nothing serves it)
#   - it is connected to a *different* bucket
#   - DNS has not propagated, so the request never reaches the bucket at all
#   - it is connected but public access is off for the bucket
#
# The responses distinguish these, so this collects them rather than guessing.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
OUT="$HOME/twitter_pixiv_tg_bot/data/domain-probe.txt"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo

    echo "--- what does ginka.uk resolve to? ---"
    python - <<'PY'
import socket
for host in ("ginka.uk", "www.ginka.uk"):
    try:
        infos = socket.getaddrinfo(host, 443, socket.AF_INET)
        print(f"  {host:16} {', '.join(sorted({i[4][0] for i in infos})[:4])}")
    except Exception as exc:
        print(f"  {host:16} FAILED: {type(exc).__name__}")
PY
    echo

    echo "--- Cloudflare ranges are 104.x, 172.6x, 188.114.x - which of those is it? ---"
    echo "  (R2 custom domains answer from Cloudflare's edge, so a non-Cloudflare address means"
    echo "   the domain is not connected to R2 at all)"
    echo

    echo "--- the root of the domain ---"
    curl -s -o /dev/null -w '  ginka.uk/            -> HTTP %{http_code}  server=%{scheme}\n' \
        --max-time 20 https://ginka.uk/ 2>&1
    echo

    echo "--- response headers from the root ---"
    curl -sI --max-time 20 https://ginka.uk/ 2>&1 | head -12 | sed 's/^/  /'
    echo

    echo "--- a path that does not exist, to see whose 404 it is ---"
    curl -sI --max-time 20 https://ginka.uk/definitely-not-here-12345 2>&1 \
        | grep -iE '^HTTP|server|cf-ray|content-type' | sed 's/^/  /'
    echo

    echo "--- does the R2 bucket respond under its r2.dev name, if public access is on? ---"
    # The r2.dev URL is derived from the account, which is known. It is rate limited, but its answer
    # says whether the bucket itself is publicly readable - which separates "bucket not public" from
    # "domain not connected".
    ACCOUNT=$(grep -m1 '^R2_ACCOUNT_ID=' "$HOME/twitter_pixiv_tg_bot/.env" | cut -d= -f2- | tr -d '\r')
    echo "  account: $ACCOUNT"
    echo "  (the r2.dev subdomain is random, so it cannot be derived - open R2 -> bucket ->"
    echo "   Settings -> Public access to read it if one was enabled)"
} > "$OUT" 2>&1

echo "written to $OUT"

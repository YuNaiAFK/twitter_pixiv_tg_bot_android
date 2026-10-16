#!/data/data/com.termux/files/usr/bin/bash
# Can boto3 be installed here, or does the uploader need its own SigV4 signing?
#
# boto3 is the obvious way to talk to R2's S3-compatible API, but it is a large dependency
# (boto3 + botocore + s3transfer + jmespath + urllib3) on a phone, and pip needs the proxy. This
# records whether it installs, how long it takes, and how much it costs in disk - so the choice
# between using it and writing SigV4 by hand is made on evidence.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
OUT="$HOME/twitter_pixiv_tg_bot/data/r2-dep-check.txt"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo

    echo "--- is it already there? ---"
    python -c "import boto3; print('  boto3', boto3.__version__)" 2>&1 | sed 's/^/  /'
    python -c "import botocore; print('  botocore', botocore.__version__)" 2>&1 | sed 's/^/  /'
    echo

    echo "--- free space before ---"
    df -h "$PREFIX" | tail -1 | sed 's/^/  /'
    echo

    echo "--- the proxy pip needs ---"
    if [ -f "$HOME/.proxy-url" ]; then
        echo "  $(cat "$HOME/.proxy-url")"
    else
        echo "  (no ~/.proxy-url)"
    fi
    echo

    PROXY=$(cat "$HOME/.proxy-url" 2>/dev/null || echo "")
    echo "--- pip install boto3 --dry-run (does it resolve?) ---"
    started=$(date +%s)
    if [ -n "$PROXY" ]; then
        timeout 180 python -m pip install --dry-run --proxy "$PROXY" boto3 2>&1 | tail -12 | sed 's/^/  /'
    else
        timeout 180 python -m pip install --dry-run boto3 2>&1 | tail -12 | sed 's/^/  /'
    fi
    echo "  exit: $?  elapsed: $(( $(date +%s) - started ))s"
    echo

    echo "--- what it would pull in ---"
    if [ -n "$PROXY" ]; then
        timeout 180 python -m pip download --no-deps --dest /tmp/r2probe --proxy "$PROXY" \
            boto3 botocore s3transfer jmespath 2>&1 | tail -6 | sed 's/^/  /'
    fi
    if [ -d /tmp/r2probe ]; then
        du -sh /tmp/r2probe 2>/dev/null | sed 's/^/  total: /'
        ls /tmp/r2probe | sed 's/^/    /'
        rm -rf /tmp/r2probe
    fi
} > "$OUT" 2>&1

echo "written to $OUT"

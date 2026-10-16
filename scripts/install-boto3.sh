#!/data/data/com.termux/files/usr/bin/bash
# Install boto3, which is how the bot will talk to R2.
#
# R2 speaks the S3 API, so boto3 works against it with a custom endpoint. Hand-rolling SigV4 signing
# was the alternative and it is roughly a hundred lines of crypto to get subtly wrong; boto3
# resolves in seven seconds here and every wheel is pure Python, so there is no reason to.
#
# pip needs the proxy: PyPI is not reachable directly from this network. The URL comes from
# ~/.proxy-url, which the earlier proxy work left in place.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
OUT="$HOME/twitter_pixiv_tg_bot/data/boto3-install.txt"

PROXY=$(cat "$HOME/.proxy-url" 2>/dev/null | tr -d '\r\n')
PROXY="${PROXY:-http://127.0.0.1:10808}"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo "  proxy: $PROXY"
    echo

    echo "--- already installed? ---"
    python -c "
try:
    import boto3, botocore
    print('  boto3', boto3.__version__, '/ botocore', botocore.__version__)
except ImportError as exc:
    print('  not installed:', exc)
"
    echo

    echo "--- installing ---"
    started=$(date +%s)
    # TMPDIR is set because /tmp does not exist for Termux and pip writes build artefacts there.
    TMPDIR="$PREFIX/tmp" python -m pip install --no-input --proxy "$PROXY" boto3 2>&1 | tail -12
    echo "  exit: $?  elapsed: $(( $(date +%s) - started ))s"
    echo

    echo "--- verify it imports and can be pointed at R2 ---"
    python - <<'PY'
try:
    import boto3
    from botocore.config import Config
    # Constructing a client against an R2 endpoint needs no credentials to succeed; it only proves
    # the library is importable and the S3 API surface is there.
    session = boto3.session.Session()
    client = session.client(
        "s3",
        endpoint_url="https://example.r2.cloudflarestorage.com",
        aws_access_key_id="probe",
        aws_secret_access_key="probe",
        region_name="auto",
        config=Config(signature_version="s3v4", retries={"max_attempts": 2}),
    )
    print("  client constructed ok")
    print("  operations available:", ", ".join(
        sorted(n for n in dir(client) if n in
               ("put_object", "get_object", "head_object", "delete_object", "list_objects_v2"))))
except Exception as exc:
    print("  FAILED:", type(exc).__name__, exc)
PY
} > "$OUT" 2>&1

echo "written to $OUT"

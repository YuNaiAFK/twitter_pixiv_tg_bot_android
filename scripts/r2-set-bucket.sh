#!/data/data/com.termux/files/usr/bin/bash
# Record the bucket name that list_buckets actually returned, rather than a guessed one.
#
# The guess was "gallery" and the real name is "picture". A wrong bucket name would have produced
# NoSuchBucket on the first upload - which is at least an honest error, but it would have arrived
# after the download of a gallery's worth of images.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"

PROJECT_DIR="$HOME/twitter_pixiv_tg_bot"
ENV_FILE="$PROJECT_DIR/.env"
BUCKET="${1:-}"
OUT="$PROJECT_DIR/data/r2-bucket.txt"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="

    if [ -z "$BUCKET" ]; then
        echo "  usage: $0 <bucket-name>"
        exit 2
    fi

    if grep -q '^R2_BUCKET=' "$ENV_FILE" 2>/dev/null; then
        grep -v '^R2_BUCKET=' "$ENV_FILE" > "$ENV_FILE.tmp" && mv "$ENV_FILE.tmp" "$ENV_FILE"
    fi
    printf 'R2_BUCKET=%s\n' "$BUCKET" >> "$ENV_FILE"

    echo "  R2_BUCKET set to $BUCKET"
    echo
    echo "--- R2 settings in .env now ---"
    grep -E '^R2_' "$ENV_FILE" \
        | sed 's/^\(R2_\(ACCESS_KEY\|SECRET_KEY\)=\).*/\1<masked>/' | sed 's/^/  /'
} > "$OUT" 2>&1

echo "written to $OUT"

#!/data/data/com.termux/files/usr/bin/bash
# Write the R2 ceiling settings into .env explicitly.
#
# They have defaults, but a limit nobody can see is a limit nobody will adjust - and the point of
# the ceiling is that the operator knows where it is. Written explicitly so changing it is an edit to
# a line that exists rather than to documentation about a default.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
ENV_FILE="$HOME/twitter_pixiv_tg_bot/.env"
OUT="$HOME/twitter_pixiv_tg_bot/data/r2-settings.txt"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo

    set_setting() {
        local key="$1" value="$2"
        if grep -q "^$key=" "$ENV_FILE" 2>/dev/null; then
            # Only rewrite when the value differs, so running this twice is not a diff.
            current=$(grep -m1 "^$key=" "$ENV_FILE" | cut -d= -f2-)
            if [ "$current" = "$value" ]; then
                printf '  %-20s already %s\n' "$key" "$value"
                return
            fi
            grep -v "^$key=" "$ENV_FILE" > "$ENV_FILE.tmp" && mv "$ENV_FILE.tmp" "$ENV_FILE"
        fi
        printf '%s=%s\n' "$key" "$value" >> "$ENV_FILE"
        printf '  %-20s set to %s\n' "$key" "$value"
    }

    echo "--- writing the ceiling settings ---"
    # 10 GB, the free allowance, in decimal bytes - what Cloudflare bills in.
    set_setting R2_FREE_BYTES 10000000000
    # Stop at 95%. Storage is billed monthly and by the time an object exists, so reaching the
    # allowance exactly and pruning later still exceeds it for that month.
    set_setting R2_LIMIT_PERCENT 95
    echo

    echo "--- the R2 block in .env now ---"
    grep '^R2_' "$ENV_FILE" | sed 's/^\(R2_\(ACCESS_KEY\|SECRET_KEY\)=\).*/\1<masked>/' | sed 's/^/  /'
} > "$OUT" 2>&1

echo "written to $OUT"

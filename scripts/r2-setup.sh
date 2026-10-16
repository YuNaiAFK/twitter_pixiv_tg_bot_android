#!/data/data/com.termux/files/usr/bin/bash
# Load the R2 credentials from the staged file into .env, then delete the staged file.
#
# The values arrive in a file rather than as command arguments so they never appear in a process
# list, and the file is removed as soon as it has been read. They still have to be handled at all
# because the operator pasted them into the conversation when asking for them to be filled in, which
# is why the token should be rotated once everything is confirmed working.
#
# The account id is derived from the endpoint rather than asked for separately: R2 endpoints are
# https://<account-id>.r2.cloudflarestorage.com, so the value is already in what the dashboard shows.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"

PROJECT_DIR="$HOME/twitter_pixiv_tg_bot"
ENV_FILE="$PROJECT_DIR/.env"
SOURCE="/data/local/tmp/botstage/r2-values.txt"
OUT="$PROJECT_DIR/data/r2-setup.txt"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo

    if [ ! -s "$SOURCE" ]; then
        echo "  *** $SOURCE is missing ***"
        exit 1
    fi

    # Format: one KEY=VALUE per line. Comment lines and blanks are ignored.
    echo "--- reading the credential file ---"
    while IFS= read -r line; do
        case "$line" in
            ''|'#'*) continue ;;
        esac
        key="${line%%=*}"
        value="${line#*=}"
        case "$key" in
            R2_ACCOUNT_ID|R2_ACCESS_KEY|R2_SECRET_KEY|R2_BUCKET|R2_PUBLIC_BASE) ;;
            *) echo "  ignoring unknown key '$key'"; continue ;;
        esac

        # Drop any existing line first: a duplicate would leave the old one in place and
        # `grep -m1` takes the first match, so the edit would silently do nothing.
        if grep -q "^$key=" "$ENV_FILE" 2>/dev/null; then
            grep -v "^$key=" "$ENV_FILE" > "$ENV_FILE.tmp" && mv "$ENV_FILE.tmp" "$ENV_FILE"
        fi
        printf '%s=%s\n' "$key" "$value" >> "$ENV_FILE"
        printf '  set %-16s (%d characters)\n' "$key" "${#value}"
    done < "$SOURCE"
    echo

    rm -f "$SOURCE"
    echo "  credential file removed"
    echo

    echo "--- what .env now holds (secrets masked) ---"
    grep -E '^R2_' "$ENV_FILE" 2>/dev/null \
        | sed 's/^\(R2_\(ACCESS_KEY\|SECRET_KEY\)=\).*/\1<masked>/' | sed 's/^/  /'
    echo
} > "$OUT" 2>&1

echo "written to $OUT"

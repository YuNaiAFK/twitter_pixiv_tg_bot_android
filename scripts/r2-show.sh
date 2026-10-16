#!/data/data/com.termux/files/usr/bin/bash
# Show the R2 block in .env with the secrets masked, and say what is still missing.
#
# Written as a script rather than a one-liner because the quoting for a pattern like "^R2_" does not
# survive PowerShell -> adb -> su, and a grep that quietly matches nothing looks exactly like a
# setting that was never written.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"

ENV_FILE="$HOME/twitter_pixiv_tg_bot/.env"

echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
echo

echo "--- the R2 block in .env (secrets masked) ---"
grep '^R2_' "$ENV_FILE" 2>/dev/null \
    | sed 's/^\(R2_\(ACCESS_KEY\|SECRET_KEY\)=\).*/\1<masked>/' \
    | sed 's/^/  /'
echo

echo "--- how many lines, and which are present ---"
total=$(grep -c '^R2_' "$ENV_FILE" 2>/dev/null || echo 0)
echo "  total R2 lines: $total"
for key in R2_ACCOUNT_ID R2_ACCESS_KEY R2_SECRET_KEY R2_BUCKET R2_PUBLIC_BASE; do
    if grep -q "^$key=" "$ENV_FILE" 2>/dev/null; then
        value=$(grep -m1 "^$key=" "$ENV_FILE" | cut -d= -f2-)
        if [ -n "$value" ]; then
            printf '  %-18s set (%d chars)\n' "$key" "${#value}"
        else
            printf '  %-18s EMPTY\n' "$key"
        fi
    else
        printf '  %-18s MISSING\n' "$key"
    fi
done

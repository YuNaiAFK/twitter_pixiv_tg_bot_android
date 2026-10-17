#!/data/data/com.termux/files/usr/bin/bash
# Who can the bot notify, and are the R2 ceiling settings present?
#
# The notification path is worthless without an administrator configured, and that is exactly the
# kind of thing that only shows up when it is needed. This reports it now instead.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
OUT="$HOME/twitter_pixiv_tg_bot/data/admin-check.txt"
cd "$HOME/twitter_pixiv_tg_bot/bot" || exit 1

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo

    echo "--- .env settings that matter here ---"
    for key in ADMIN_IDS ADMIN_USER_IDS AUTH_FILE R2_FREE_BYTES R2_LIMIT_PERCENT; do
        line=$(grep -m1 "^$key=" "$HOME/twitter_pixiv_tg_bot/.env" 2>/dev/null)
        if [ -n "$line" ]; then
            printf '  %-20s %s\n' "$key" "${line#*=}"
        else
            printf '  %-20s (not set)\n' "$key"
        fi
    done
    echo

    python - <<'PY'
import sys
from pathlib import Path

sys.path.insert(0, ".")
sys.path.insert(0, "vendor")

import bot
import r2

print("--- administrators the bot knows about ---")
admins = sorted(bot.ADMIN_USER_IDS)
if admins:
    for admin in admins:
        print(f"  {admin}")
else:
    print("  NONE - the budget notice cannot be delivered")
    print("  set ADMIN_IDS in .env, or promote a user with /promote in a private chat")
print()

print("--- the authorization file ---")
try:
    print(f"  path: {bot.AUTH_FILE}")
    print(f"  exists: {Path(bot.AUTH_FILE).exists()}")
    if Path(bot.AUTH_FILE).exists():
        print(f"  size: {Path(bot.AUTH_FILE).stat().st_size} bytes")
except Exception as exc:
    print(f"  {type(exc).__name__}: {exc}")
print()

print("--- the R2 ceiling ---")
print(f"  allowance: {r2.format_bytes(r2.free_bytes())} ({r2.free_bytes()} bytes)")
print(f"  limit:     {r2.format_bytes(r2.limit_bytes())} "
      f"({r2.limit_percent():.0f}% of the allowance)")
print()

print("--- and the bucket's current usage ---")
settings = r2.r2_settings()
if settings is None:
    print("  R2 is not configured")
else:
    try:
        used, count = r2.bucket_usage(settings, timeout=120)
        print(f"  {r2.budget_line(used, count)}")
        remaining = r2.limit_bytes() - used
        if remaining > 0:
            print(f"  remaining before the ceiling: {r2.format_bytes(remaining)}")
            print(f"  roughly {int(remaining / (30 * 1000 * 1000))} more galleries "
                  f"at 30 MB each")
        else:
            print("  *** the ceiling is already reached - uploads will be refused ***")
    except r2.R2Error as exc:
        print(f"  FAILED: {exc}")
PY
} > "$OUT" 2>&1

echo "written to $OUT"

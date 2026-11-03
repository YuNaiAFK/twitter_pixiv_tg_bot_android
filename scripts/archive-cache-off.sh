#!/data/data/com.termux/files/usr/bin/bash
# Turn off the archive cache and reclaim what it holds.
#
# The operator's reason was "本子走的是r2，不需要本地快取" - galleries are served from R2, so nothing
# local is needed. That is exactly right about the **page images**: a Telegraph parse streams each
# image to R2 and never writes it to disk. What *is* on disk for a gallery is the official archive,
# kept so a repeat of 歸檔 does not re-download ninety megabytes.
#
# So this disables that one cache. The 156 MB of Twitter/Pixiv media is a different thing with a
# different justification - a repeat parse of an X link is served from it in milliseconds instead of
# being downloaded again - and it is left alone unless asked for.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
OUT="$HOME/twitter_pixiv_tg_bot/data/archive-cache-off.txt"
PROJECT="$HOME/twitter_pixiv_tg_bot"
ENV_FILE="$PROJECT/.env"
STAMP=$(date '+%Y%m%d-%H%M%S')

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo

    echo "--- before ---"
    du -sh "$PROJECT/.cache" 2>/dev/null | sed 's/^/  /'
    du -sh "$PROJECT/.cache/archives" 2>/dev/null | sed 's/^/  /'
    grep -n '^ARCHIVE_CACHE=' "$ENV_FILE" 2>/dev/null | sed 's/^/  /' || echo "  ARCHIVE_CACHE: not set (defaults to on)"
    echo

    echo "--- turning ARCHIVE_CACHE off in .env ---"
    if grep -q '^ARCHIVE_CACHE=' "$ENV_FILE" 2>/dev/null; then
        sed -i 's|^ARCHIVE_CACHE=.*|ARCHIVE_CACHE=0|' "$ENV_FILE"
        echo "  set to 0"
    else
        printf '\n# Galleries are served from R2, so the official archive is re-downloaded on demand\n# rather than kept locally. Set to 1 to cache it again.\nARCHIVE_CACHE=0\n' >> "$ENV_FILE"
        echo "  added ARCHIVE_CACHE=0"
    fi
    grep -n '^ARCHIVE_CACHE=' "$ENV_FILE" | sed 's/^/  /'
    echo

    echo "--- deleting the cached archives ---"
    if [ -d "$PROJECT/.cache/archives" ]; then
        before=$(du -sm "$PROJECT/.cache/archives" 2>/dev/null | cut -f1)
        find "$PROJECT/.cache/archives" -type f -delete 2>/dev/null
        # The directory stays: archive_cache_path globs it, and removing it while the bot runs would
        # make the next lookup fail rather than return "no entry".
        after=$(du -sm "$PROJECT/.cache/archives" 2>/dev/null | cut -f1)
        echo "  ${before} MB -> ${after} MB"
    else
        echo "  no archive directory"
    fi
    echo

    echo "--- what is left, and what it belongs to ---"
    du -sh "$PROJECT/.cache" 2>/dev/null | sed 's/^/  total: /'
    echo "  loose files: $(find "$PROJECT/.cache" -maxdepth 1 -type f 2>/dev/null | wc -l)"
    python - <<'PY'
import sys
from collections import Counter
sys.path.insert(0, ".")
import bot

kinds = Counter((e or {}).get("kind", "?") for e in bot.PARSE_CACHE.entries.values())
print(f"  cache entries: {dict(kinds)}")
files = sum(len((e or {}).get("payload", {}).get("files") or [])
            for e in bot.PARSE_CACHE.entries.values())
print(f"  files referenced by those entries: {files}")
print("  (all of them belong to media parses - Twitter and Pixiv)")
PY
    echo

    echo "--- restarting so the setting takes effect ---"
    bash "$PROJECT/scripts/run-bot.sh" --stop 2>&1 | tail -2 | sed 's/^/  /'
    sleep 2
    bash "$PROJECT/scripts/run-bot.sh" --background 2>&1 | tail -4 | sed 's/^/  /'
    sleep 8
    bash "$PROJECT/scripts/run-bot.sh" --status 2>&1 | head -4 | sed 's/^/  /'
} > "$OUT" 2>&1

echo "written to $OUT"

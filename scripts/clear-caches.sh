#!/data/data/com.termux/files/usr/bin/bash
# Clear every cache, now that the paths resolve correctly.
#
# Runs the same code /cache clear runs, rather than deleting files by hand, so what gets cleared is
# exactly what the command would clear - and any disagreement between the two shows up here instead
# of in the operator's hands.
#
# The bot keeps its own state in memory, so a restart afterwards is what actually clears the
# regenerate map and the cookie memo for the running process. Both are also cleared here for the
# benefit of a bot that is already running with the new code.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
OUT="$HOME/twitter_pixiv_tg_bot/data/clear-caches.txt"
cd "$HOME/twitter_pixiv_tg_bot/bot" || exit 1

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo

    python - <<'PY'
import sys
from pathlib import Path

sys.path.insert(0, ".")
sys.path.insert(0, "vendor")

import bot
import ehentai

print("--- effective paths ---")
for label, path in (("PROJECT_DIR", bot.PROJECT_DIR), ("CACHE_FILE", bot.CACHE_FILE),
                    ("CACHE_DIR", bot.CACHE_DIR), ("ARCHIVE_CACHE_DIR", bot.ARCHIVE_CACHE_DIR)):
    p = Path(path)
    if p.is_file():
        detail = f"{p.stat().st_size} bytes"
    elif p.is_dir():
        detail = f"{sum(1 for f in p.rglob('*') if f.is_file())} files"
    else:
        detail = "absent"
    print(f"  {label:18} {str(p):<58} {detail}")
print()

print("--- safety check ---")
for label, path in (("CACHE_DIR", bot.CACHE_DIR), ("ARCHIVE_CACHE_DIR", bot.ARCHIVE_CACHE_DIR)):
    p = Path(path)
    if p.exists():
        print(f"  {label:18} is_safe_to_clear = {bot.is_safe_to_clear(p)}")
    else:
        print(f"  {label:18} does not exist (check skipped, which is correct)")
print()

print("--- before ---")
entries_before = len(bot.PARSE_CACHE.entries)
print(f"  parse cache entries:     {entries_before}")
print(f"  regenerate map:          {len(bot._regenerate_cache)}")
print(f"  cookie header memo:      {len(ehentai._cookie_header_cache)}")
print()

# The same three steps cache_command performs, in the same order.
cached_files = [p for p in Path(bot.CACHE_DIR).rglob("*")
                if p.is_file() and Path(bot.ARCHIVE_CACHE_DIR) not in p.parents] \
    if Path(bot.CACHE_DIR).is_dir() else []
archive_files = [p for p in Path(bot.ARCHIVE_CACHE_DIR).glob("*") if p.is_file()] \
    if Path(bot.ARCHIVE_CACHE_DIR).is_dir() else []

print("--- deleting ---")
removed = bot.delete_files_quietly(cached_files)
archives = bot.delete_files_quietly(archive_files)
print(f"  cache dir files:  {removed}")
print(f"  archive files:    {archives}")

bot._regenerate_cache.clear()
ehentai._cookie_header_cache.clear()
bot.PARSE_CACHE.entries.clear()
bot.PARSE_CACHE.hits = 0
bot.PARSE_CACHE.misses = 0
print("  in-memory state cleared")

parse_state = "absent"
try:
    if Path(bot.PARSE_CACHE.path).exists():
        size = Path(bot.PARSE_CACHE.path).stat().st_size
        Path(bot.PARSE_CACHE.path).unlink()
        parse_state = f"deleted ({size} bytes)"
except OSError as exc:
    parse_state = f"failed: {exc}"
print(f"  parse cache file: {parse_state}")

orphans = bot.prune_orphaned_cache_files()
print(f"  orphaned files:   {orphans} removed")
print()

print("--- after ---")
for label, path in (("CACHE_FILE", bot.PARSE_CACHE.path), ("CACHE_DIR", bot.CACHE_DIR),
                    ("ARCHIVE_CACHE_DIR", bot.ARCHIVE_CACHE_DIR)):
    p = Path(path)
    if p.exists():
        if p.is_file():
            print(f"  {label:18} still exists: {p} ({p.stat().st_size} bytes)  *** LEFTOVER ***")
        else:
            left = [f for f in p.rglob("*") if f.is_file()]
            print(f"  {label:18} still exists: {len(left)} files  "
                  + ("*** LEFTOVER ***" if left else "(empty, which is fine)"))
    else:
        print(f"  {label:18} gone")
print(f"  parse cache entries:     {len(bot.PARSE_CACHE.entries)}")
print(f"  regenerate map:          {len(bot._regenerate_cache)}")
print(f"  cookie header memo:      {len(ehentai._cookie_header_cache)}")
PY
} > "$OUT" 2>&1

echo "written to $OUT"

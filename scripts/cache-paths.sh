#!/data/data/com.termux/files/usr/bin/bash
# What are the effective cache paths, and would /cache clear accept them?
#
# is_safe_to_clear requires the path to be inside BASE_DIR, which is the directory bot.py lives in -
# bot/. But the parse cache file is at the project root, so the configuration already puts cache data
# outside that directory. If CACHE_DIR is set the same way, the safety check refuses and /cache clear
# does nothing but print a refusal, which is the "cache clearing problem".
#
# This asks the running code rather than reading .env, because the defaults and the overrides are
# applied in several places and only the module knows the result.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
OUT="$HOME/twitter_pixiv_tg_bot/data/cache-paths.txt"
cd "$HOME/twitter_pixiv_tg_bot/bot" || exit 1

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo

    echo "--- the cache settings in .env ---"
    grep -E '^(CACHE|ARCHIVE|WORK_DIR)' "$HOME/twitter_pixiv_tg_bot/.env" 2>/dev/null | sed 's/^/  /'
    echo "  (nothing above means the defaults are in use)"
    echo

    python - <<'PY'
import sys
from pathlib import Path

sys.path.insert(0, ".")
sys.path.insert(0, "vendor")

import bot

print("--- the effective paths, as the running code sees them ---")
rows = [
    ("BASE_DIR", bot.BASE_DIR),
    ("CACHE_FILE", bot.CACHE_FILE),
    ("CACHE_DIR", bot.CACHE_DIR),
    ("ARCHIVE_CACHE_DIR", bot.ARCHIVE_CACHE_DIR),
    ("PARSE_CACHE.path", bot.PARSE_CACHE.path),
]
for label, path in rows:
    exists = "exists" if Path(path).exists() else "       "
    size = ""
    try:
        p = Path(path)
        if p.is_file():
            size = f"{p.stat().st_size:>10} bytes"
        elif p.is_dir():
            count = sum(1 for _ in p.rglob("*") if _.is_file()) if p.is_dir() else 0
            size = f"{count:>10} files"
    except OSError:
        size = "     ?"
    print(f"  {label:20} {str(path):<62} {exists} {size}")
print()

print("--- would /cache clear accept them? ---")
for label, path in (("CACHE_DIR", bot.CACHE_DIR), ("ARCHIVE_CACHE_DIR", bot.ARCHIVE_CACHE_DIR)):
    p = Path(path)
    if not p.exists():
        print(f"  {label:18} does not exist yet - the check is skipped")
        continue
    safe = bot.is_safe_to_clear(p)
    print(f"  {label:18} is_safe_to_clear = {safe}"
          + ("" if safe else "   <<< /cache clear would REFUSE"))
    if not safe:
        print(f"      resolved: {p.resolve()}")
        print(f"      BASE_DIR: {bot.BASE_DIR.resolve()}")
        try:
            p.resolve().relative_to(bot.BASE_DIR.resolve())
            print("      it is inside BASE_DIR after all")
        except ValueError:
            print("      NOT inside BASE_DIR - that is why it is refused")
print()

print("--- what the parse cache actually holds ---")
entries = bot.PARSE_CACHE.entries
print(f"  entries: {len(entries)}")
kinds = {}
for key, entry in entries.items():
    kind = (entry or {}).get("kind", "?")
    kinds[kind] = kinds.get(kind, 0) + 1
for kind, count in sorted(kinds.items()):
    print(f"    {kind}: {count}")

# Which of them carry the things a stale cache would keep serving.
with_r2 = sum(1 for e in entries.values() if ((e or {}).get("payload") or {}).get("r2"))
with_page = sum(1 for e in entries.values() if ((e or {}).get("payload") or {}).get("telegraph"))
print(f"  with R2 urls: {with_r2}")
print(f"  with a Telegraph page: {with_page}")
print()

print("--- the in-memory state /cache clear does NOT touch ---")
print(f"  _regenerate_cache entries: {len(bot._regenerate_cache)}")
print("    (the 重新生成 button reads this; clearing the disk cache leaves it behind)")
print()

print("--- other caches on disk ---")
for label, path in (("parse cache file", Path(bot.PARSE_CACHE.path)),
                    ("cache dir", Path(bot.CACHE_DIR)),
                    ("archive cache", Path(bot.ARCHIVE_CACHE_DIR))):
    p = Path(path)
    if not p.exists():
        print(f"  {label:18} {p}  (absent)")
        continue
    if p.is_file():
        print(f"  {label:18} {p}  {p.stat().st_size} bytes")
    else:
        files = [f for f in p.rglob("*") if f.is_file()]
        total = sum(f.stat().st_size for f in files)
        print(f"  {label:18} {p}  {len(files)} files, {total / 1024 / 1024:.1f} MB")

# And the cookie header memo, which is a cache in the same sense.
import ehentai
print(f"  cookie header memo {len(ehentai._cookie_header_cache)} entries")
PY
} > "$OUT" 2>&1

echo "written to $OUT"

#!/data/data/com.termux/files/usr/bin/bash
# What does the parse cache actually contain, and are the 146 files referenced?
#
# The first audit read a top-level "entries" key and found nothing, which contradicted a 151 KB file.
# The guess was wrong, not the cache - so this prints the real shape rather than assuming it again.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
OUT="$HOME/twitter_pixiv_tg_bot/data/cache-shape.txt"
cd "$HOME/twitter_pixiv_tg_bot/bot" || exit 1

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo
    python - <<'PY'
import json
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, ".")
sys.path.insert(0, "vendor")

path = Path.home() / "twitter_pixiv_tg_bot" / "parse_cache.json"
raw = path.read_text(encoding="utf-8")
data = json.loads(raw)

print("--- top-level shape ---")
print(f"  type: {type(data).__name__}")
if isinstance(data, dict):
    for key, value in list(data.items())[:6]:
        kind = type(value).__name__
        size = len(value) if hasattr(value, "__len__") else "?"
        print(f"  {key!r:16} {kind} of {size}")

# The bot's own loader is the authority on the shape.
import bot

cache = bot.PARSE_CACHE
print()
print(f"--- via bot.PARSE_CACHE ---")
print(f"  entries: {len(cache.entries)}")
kinds = Counter((entry or {}).get("kind", "?") for entry in cache.entries.values())
for kind, count in kinds.most_common():
    print(f"    {kind:10} {count}")

referenced = set()
for entry in cache.entries.values():
    for name in (entry.get("payload") or {}).get("files") or []:
        if isinstance(name, str):
            referenced.add(name)
print(f"  file names referenced: {len(referenced)}")
print()

print("--- on disk vs referenced ---")
root = bot.CACHE_DIR
on_disk = {p.name for p in root.glob("*") if p.is_file()}
print(f"  on disk:     {len(on_disk)}")
print(f"  referenced:  {len(referenced & on_disk)} of those")
orphans = sorted(on_disk - referenced)
print(f"  orphans:     {len(orphans)}")
total = 0
for name in orphans[:5]:
    try:
        total += (root / name).stat().st_size
    except OSError:
        pass
if orphans:
    print(f"  first few:   {orphans[:5]}")
print()

print("--- what bot.orphaned_cache_files() says ---")
found = bot.orphaned_cache_files()
size = 0
for p in found:
    try:
        size += p.stat().st_size
    except OSError:
        pass
print(f"  {len(found)} files, {size / 1024 / 1024:.1f} MB")
PY
} > "$OUT" 2>&1

echo "written to $OUT"

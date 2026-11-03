#!/data/data/com.termux/files/usr/bin/bash
# What do the 15 gallery entries actually hold, and how much space do they take?
#
# "e-hentai does not need cache" is unambiguous about the archive, which is now off and deleted. The
# remaining gallery entries are a different question: they are kilobytes, not megabytes, and they hold
# the Telegraph page URL and the R2 URLs. Delete them and the next parse of a gallery creates a
# *second* Telegraph page, because reuse is what the entry is for. Worth measuring before removing.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
OUT="$HOME/twitter_pixiv_tg_bot/data/gallery-entries.txt"
cd "$HOME/twitter_pixiv_tg_bot/bot" || exit 1

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo
    python - <<'PY'
import json
import sys

sys.path.insert(0, ".")
sys.path.insert(0, "vendor")

import bot

cache = bot.PARSE_CACHE
galleries = {k: v for k, v in cache.entries.items()
             if (v or {}).get("kind") == "gallery"}
media = {k: v for k, v in cache.entries.items()
         if (v or {}).get("kind") == "media"}

print(f"  gallery entries: {len(galleries)}")
print(f"  media entries:   {len(media)}")
print()

gallery_bytes = len(json.dumps(galleries, ensure_ascii=False).encode())
media_bytes = len(json.dumps(media, ensure_ascii=False).encode())
print(f"  gallery entries serialise to {gallery_bytes / 1024:.1f} KB")
print(f"  media entries serialise to   {media_bytes / 1024:.1f} KB")
print()

print("--- what one gallery entry holds ---")
for key, value in list(galleries.items())[:1]:
    payload = (value or {}).get("payload") or {}
    print(f"  key: {key[:70]}")
    print(f"  payload keys: {sorted(payload)}")
    gallery = payload.get("gallery") or {}
    print(f"  gallery keys: {sorted(gallery)[:12]}")
    print(f"  display_urls: {len(payload.get('display_urls') or [])}")
    print(f"  telegraph:    {payload.get('telegraph') or '(none)'}")
print()

print("--- across all gallery entries ---")
with_telegraph = sum(1 for v in galleries.values()
                     if ((v or {}).get("payload") or {}).get("telegraph"))
with_sweep = sum(1 for v in galleries.values()
                 if ((v or {}).get("payload") or {}).get("display_urls"))
print(f"  holding a Telegraph page record: {with_telegraph}")
print(f"  holding a swept image list:      {with_sweep}")
print()
print("  A gallery entry without its Telegraph record re-creates the page on the next parse:")
print("  the reuse path is what stops a second page for the same gallery.")
PY
} > "$OUT" 2>&1

echo "written to $OUT"

#!/data/data/com.termux/files/usr/bin/bash
# Compare a cached gallery's tags against e-hentai's current ones.
#
# The report is "本子的tag更新的时候bot好像没更新" - a gallery's tags change on e-hentai and the bot keeps
# showing the old set. GALLERY_META_TTL_SECONDS was added for that and evidently is not the whole story,
# so this measures instead of assuming: read what the cache holds, fetch the same gallery live, and
# diff the two tag lists.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
OUT="$HOME/twitter_pixiv_tg_bot/data/tag-diff.txt"
cd "$HOME/twitter_pixiv_tg_bot/bot" || exit 1

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo
    python - <<'PY'
import sys
import time

sys.path.insert(0, ".")
sys.path.insert(0, "vendor")

import bot
import ehentai

print(f"  GALLERY_META_TTL_SECONDS = {bot.GALLERY_META_TTL_SECONDS} s"
      f"  ({bot.GALLERY_META_TTL_SECONDS / 3600:.1f} h)")
print(f"  CACHE_STALE_SECONDS      = {bot.CACHE_STALE_SECONDS} s"
      f"  ({bot.CACHE_STALE_SECONDS / 86400:.1f} d)")
print()

galleries = [(k, v) for k, v in bot.PARSE_CACHE.entries.items()
             if (v or {}).get("kind") == "gallery"]
print(f"  cached galleries: {len(galleries)}")
print()

cookies = bot.resolve_ehentai_cookies()
for key, entry in galleries[:3]:
    payload = (entry or {}).get("payload") or {}
    cached = bot.gallery_from_payload(payload)
    if cached is None:
        print(f"  {key}: cannot rebuild from cache")
        continue

    age = bot.gallery_cache_age(key)
    print(f"--- {key}")
    print(f"  cache age: {age:.0f} s ({age / 3600:.1f} h)" if age else "  cache age: unknown")

    cached_tags = sorted(cached.tags or [])
    print(f"  cached tags: {len(cached_tags)}")

    try:
        fresh = ehentai.fetch_gallery(key, cookies_path=cookies,
                                      timeout=float(bot.EHENTAI_TIMEOUT_SECONDS))
    except Exception as exc:
        print(f"  live fetch failed: {type(exc).__name__}: {str(exc)[:120]}")
        print()
        continue

    live_tags = sorted(fresh.tags or [])
    print(f"  live tags:   {len(live_tags)}")

    added = [t for t in live_tags if t not in cached_tags]
    removed = [t for t in cached_tags if t not in live_tags]
    if added or removed:
        print(f"  ** DIFFERENT **")
        if added:
            print(f"    added on e-hentai:   {added[:8]}")
        if removed:
            print(f"    removed on e-hentai: {removed[:8]}")
    else:
        print("  identical")

    # And what the bot would actually print, before and after.
    print(f"  title cached: {cached.title[:60]!r}")
    print(f"  title live:   {fresh.title[:60]!r}")
    print(f"  rating cached: {cached.rating}   live: {fresh.rating}")
    print()
    time.sleep(1.0)
PY
} > "$OUT" 2>&1

echo "written to $OUT"

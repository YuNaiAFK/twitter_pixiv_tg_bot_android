#!/data/data/com.termux/files/usr/bin/bash
# Does the deployed code actually refresh an old gallery, and what does the bot print for its tags?
#
# The cached galleries are 96-190 hours old - far past the 6 hour metadata TTL - yet their ratings
# still differ from live e-hentai, so the refresh is not firing. This reads the deployed source rather
# than the local copy, because the two have diverged before.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
OUT="$HOME/twitter_pixiv_tg_bot/data/tag-refresh-check.txt"
PROJECT="$HOME/twitter_pixiv_tg_bot"
cd "$PROJECT/bot" || exit 1

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo

    echo "--- is the refresh branch in the deployed file ---"
    grep -n "GALLERY_META_TTL_SECONDS\|畫廊資料已過期\|重新取得畫廊資料失敗" bot.py | sed 's/^/  /'
    echo

    echo "--- the deployed handler, around the cache read ---"
    awk '/cached = gallery_cache_lookup\(url\)/{found=1} found{print NR": "$0; n++} n>34{exit}' bot.py
    echo

    echo "--- what the bot would print as the info block, from cache ---"
    python - <<'PY'
import sys
import time

sys.path.insert(0, ".")
sys.path.insert(0, "vendor")

import bot
import ehentai

galleries = [(k, v) for k, v in bot.PARSE_CACHE.entries.items()
             if (v or {}).get("kind") == "gallery"]
key, entry = galleries[0]
payload = (entry or {}).get("payload") or {}
cached = bot.gallery_from_payload(payload)
age = bot.gallery_cache_age(key)
print(f"  gallery: {key}")
print(f"  age: {age:.0f} s ({age / 3600:.1f} h), TTL {bot.GALLERY_META_TTL_SECONDS} s")
print(f"  would refresh: {age is not None and age > bot.GALLERY_META_TTL_SECONDS}")
print()

# **The question that matters: which tags does the bot SHOW, and is the translation current?**
print("  --- the info block the bot builds from this entry ---")
info = bot.build_gallery_info(cached)
for line in info.splitlines()[:12]:
    print(f"    {line[:95]}")
print()

print("  --- raw tags on the entry vs their translations ---")
for tag in sorted(cached.tags or [])[:10]:
    translated = ehentai.translate_tag(tag)
    mark = "  " if translated != tag else "? "
    print(f"    {mark}{tag:34} -> {translated}")
PY
    echo

    echo "--- is the translation table the deployed one ---"
    ls -la tag_translations.py tag_translations_extra.py 2>/dev/null | sed 's/^/  /'
    python -c "import tag_translations as t; print('  entries:', len(t.TRANSLATIONS))" 2>&1 | sed 's/^/  /'
} > "$OUT" 2>&1

echo "written to $OUT"

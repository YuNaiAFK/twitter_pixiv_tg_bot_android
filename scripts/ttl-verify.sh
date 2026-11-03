#!/data/data/com.termux/files/usr/bin/bash
# Confirm the deployed bot re-reads gallery facts on every parse.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
OUT="$HOME/twitter_pixiv_tg_bot/data/ttl-verify.txt"
cd "$HOME/twitter_pixiv_tg_bot/bot" || exit 1

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo
    python - <<'PY'
import sys

sys.path.insert(0, ".")
sys.path.insert(0, "vendor")

import bot

print(f"  GALLERY_META_TTL_SECONDS = {bot.GALLERY_META_TTL_SECONDS}")
print(f"  CACHE_STALE_SECONDS      = {bot.CACHE_STALE_SECONDS}")
print(f"  GALLERY_URL_TTL_SECONDS  = {bot.GALLERY_URL_TTL_SECONDS}")
print()
print("  refresh decision by cache age:")
for age in (0, 30, 600, 2853, 685323):
    print(f"    {age:>7} 秒 ({age / 3600:>6.1f} h) -> "
          f"{'重新取得' if age > bot.GALLERY_META_TTL_SECONDS else '沿用快取'}")
print()
import inspect
handler = inspect.getsource(bot.handle_ehentai_gallery)
print(f"  handler 有 TTL 比較:            {'GALLERY_META_TTL_SECONDS' in handler}")
print(f"  handler 保留已掃描的圖片清單:   {'cached.get(\"display_urls\")' in handler}")
PY
} > "$OUT" 2>&1

echo "written to $OUT"

#!/data/data/com.termux/files/usr/bin/bash
# Measure what the tag dictionary costs on the phone.
#
# 543 KB of Python literal is not free: it is compiled to bytecode on first import and held in memory
# for the life of the process. This reports both, so a number is known rather than assumed - the bot
# is restarted often enough that a slow import would be felt on every restart.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
OUT="$HOME/twitter_pixiv_tg_bot/data/tag-time.txt"
cd "$HOME/twitter_pixiv_tg_bot/bot" || exit 1

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo
    python - <<'PY'
import os
import sys
import time

sys.path.insert(0, ".")
sys.path.insert(0, "vendor")

# Cold import: no .pyc yet. This is what a fresh install pays.
for cached in ("tag_translations.pyc", "tag_translations.cpython-314.pyc"):
    path = os.path.join("__pycache__", cached)
    if os.path.exists(path):
        os.remove(path)

start = time.perf_counter()
import tag_translations as tt
cold = (time.perf_counter() - start) * 1000

print(f"  冷啟動載入: {cold:.0f} ms")
print(f"  筆數:       {len(tt.TAG_TRANSLATIONS)}")
print(f"  原始補充:   ", end="")
try:
    import tag_translations_extra as ex
    print(f"{len(ex.TAG_TRANSLATIONS_EXTRA)} 筆")
except ImportError:
    print("沒有")
print()

print("  抽樣:")
for key in ("animal ears", "anal", "anal intercourse", "angel", "loli", "lolicon",
            "touhou project", "chinese", "uncensored", "nakadashi", "stomach deformation",
            "arknights", "goldenglow", "pantyhose", "big breasts", "sole female"):
    print(f"    {key:22} -> {tt.translate_tag(key)}")
print()
print(f"  未知標籤原樣回傳: {tt.translate_tag('zzz-not-a-tag')!r}")
PY
    echo
    echo "--- the generated file ---"
    ls -la "$HOME/twitter_pixiv_tg_bot/bot/tag_translations.py" | sed 's/^/  /'
    ls -la "$HOME/twitter_pixiv_tg_bot/bot/tag_translations_extra.py" | sed 's/^/  /'
} > "$OUT" 2>&1

echo "written to $OUT"

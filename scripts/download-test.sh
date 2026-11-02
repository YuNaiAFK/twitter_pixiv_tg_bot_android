#!/data/data/com.termux/files/usr/bin/bash
# Does a real download work now?
#
# The log showed gallery-dl failing with "ProxyError: Connection refused" on a network that worked
# without a proxy. grep cannot prove that is fixed, and neither can a connection test - the only
# honest check is the call that was failing: the bot's own download function against a real URL.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
OUT="$HOME/twitter_pixiv_tg_bot/data/download-test.txt"
cd "$HOME/twitter_pixiv_tg_bot/bot" || exit 1

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo
    python - <<'PY'
import os
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, ".")
sys.path.insert(0, "vendor")

import ehentai

print(f"  有效代理: {ehentai.proxy_url() or '(無，直連)'}")
print()

import bot

# The URL from the log - it failed at 07:22 with the proxy error.
URL = "https://x.com/rikak/status/2116825779673924032"

with tempfile.TemporaryDirectory() as tmp:
    out = Path(tmp)
    start = time.perf_counter()
    try:
        count = bot.download_with_gallery_dl(URL, out, bot.detect_media_platform(URL))
        elapsed = time.perf_counter() - start
        files = sorted(out.rglob("*"))
        sized = [f for f in files if f.is_file()]
        total = sum(f.stat().st_size for f in sized)
        print(f"  下載: {count} 個檔案, {total / 1024:.0f} KB, {elapsed:.1f}s")
        if count:
            print("  ✅ 成功")
            for f in sized[:3]:
                print(f"    {f.name}  {f.stat().st_size // 1024} KB")
        else:
            print("  ⚠️ 回傳 0 個檔案（可能連結已刪除或需要登入）")
    except Exception as exc:
        print(f"  ❌ 失敗: {type(exc).__name__}: {str(exc)[:400]}")
PY
} > "$OUT" 2>&1

echo "written to $OUT"

#!/data/data/com.termux/files/usr/bin/bash
# Check the image checker against real URLs, writing the result somewhere readable.
#
# **Run through RUN_COMMAND, not through `su 10209`.** A process started with su lands in the
# u:r:magisk:s0 domain, where socket creation is denied - every request fails with ConnectError and
# a working checker looks broken. RUN_COMMAND runs in Termux's own domain, which is where the bot
# itself runs, so this is also the environment the result has to be true in.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"

PROJECT_DIR="$HOME/twitter_pixiv_tg_bot"
OUT="$PROJECT_DIR/data/image-check-result.txt"
cd "$PROJECT_DIR/bot" || exit 1

{
    echo "=== run at $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo "=== domain: $(cat /proc/self/attr/current 2>/dev/null) ==="
    echo

    python - <<'PY'
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, ".")
sys.path.insert(0, "vendor")

import httpx
import ehentai

urls = []
source = ""
for name in ("parse_cache.json", "../parse_cache.json"):
    path = Path(name)
    if not path.is_file():
        continue
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        print(f"  {name}: unreadable ({exc})")
        continue
    for value in data.values():
        payload = (value or {}).get("payload") or {}
        found = payload.get("display_urls") or []
        if found:
            urls.extend(found)
    if urls:
        source = name
        break

print(f"  source: {source or '(none)'}, {len(urls)} urls")
print(f"  proxy:  {ehentai.proxy_url() or '(none)'}")
print()

if not urls:
    print("  nothing to check")
    raise SystemExit(0)

# The cached URLs are signed and may have expired since the sweep. Say so, because an expired
# signature is a legitimate "broken" and is exactly what the checker is meant to notice.
print("=== what HEAD says ===")
with httpx.Client(**ehentai.http_client_kwargs(20)) as client:
    for url in urls[:5]:
        try:
            r = client.head(url)
            ct = (r.headers.get("content-type") or "").lower().split(";")[0]
            print(f"  {r.status_code}  ct={ct or '(none)':14} len={r.headers.get('content-length') or '(none)':>9}")
        except Exception as exc:
            print(f"  ERR {type(exc).__name__}: {exc}")

print()
print("=== shallow check: 8 urls ===")
started = time.monotonic()
report = ehentai.check_image_urls(urls[:8], workers=8, timeout=20)
print(f"  {report.summary()}  ({time.monotonic() - started:.1f}s)")
for b in report.broken[:5]:
    print(f"    {b.reason}")

print()
print("=== deep check: 4 urls, bytes inspected ===")
started = time.monotonic()
deep = ehentai.check_image_urls(urls[:4], workers=4, timeout=30, deep=True)
print(f"  {deep.summary()}  ({time.monotonic() - started:.1f}s)")
for b in deep.broken[:5]:
    print(f"    {b.reason}")

print()
print("=== a small end-to-end timing on the whole list ===")
started = time.monotonic()
full = ehentai.check_image_urls(urls, workers=24, timeout=15)
elapsed = time.monotonic() - started
print(f"  {full.summary()}  ({elapsed:.1f}s for {full.checked} urls)")
PY
} > "$OUT" 2>&1

echo "written to $OUT"

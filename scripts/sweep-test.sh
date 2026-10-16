#!/data/data/com.termux/files/usr/bin/bash
# Does the sweep itself hang, independently of the bot?
#
# The bot stopped right after logging that the image list had expired and was being re-fetched, and
# both of its threads are idle - so it is waiting on something that is not thread work. The sweep is
# the first thing after that log line, and the same gallery's sweep cache was valid at 10:10, so
# 12:24 was the first time the sweep path ran since the R2 change went in.
#
# Running the sweep here, with a hard timeout around each stage, separates "the sweep is slow or
# stuck" from "the bot's own code is stuck". Nothing in this script touches R2.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
OUT="$HOME/twitter_pixiv_tg_bot/data/sweep-test.txt"
cd "$HOME/twitter_pixiv_tg_bot/bot" || exit 1

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo "  (each stage is timed, and a hard 180s timeout wraps the whole thing)"
    echo

    timeout 180 python - <<'PY'
import sys
import time
from pathlib import Path

sys.path.insert(0, ".")
sys.path.insert(0, "vendor")

URL = "https://e-hentai.org/g/4152428/95d6084b75"
COOKIES = Path("../cookies/ehentai.txt")

import ehentai

print("--- stage 1: read the gallery page ---")
started = time.monotonic()
try:
    gallery = ehentai.fetch_gallery(URL, cookies_path=COOKIES, timeout=60)
    print(f"  ok ({time.monotonic() - started:.1f}s): {gallery.title[:60]!r}")
    print(f"  filecount={gallery.filecount}")
except Exception as exc:
    print(f"  FAILED ({time.monotonic() - started:.1f}s): {type(exc).__name__}: {exc}")
    raise SystemExit(1)

print()
print("--- stage 2: the sweep (this is what the bot was doing) ---")
started = time.monotonic()
try:
    display, original = ehentai.fetch_gallery_images(
        URL, cookies_path=COOKIES, workers=6, timeout=60)
    elapsed = time.monotonic() - started
    print(f"  ok ({elapsed:.1f}s): {len(display)} display, {len(original)} original")
    if display:
        print(f"  first: {display[0][:100]}")
except Exception as exc:
    print(f"  FAILED ({time.monotonic() - started:.1f}s): {type(exc).__name__}: {exc}")
    raise SystemExit(1)

print()
print("--- stage 3: are the swept urls actually fetchable right now? ---")
import re
import httpx
for url in display[:2]:
    match = re.search(r"keystamp=(\d+)", url)
    if match:
        delta = int(match.group(1)) - int(time.time())
        print(f"  keystamp {delta:+d}s from now")
    try:
        with httpx.Client(timeout=40, follow_redirects=True) as http:
            response = http.get(url)
        print(f"  HTTP {response.status_code}  {len(response.content)} bytes")
    except Exception as exc:
        print(f"  FAILED {type(exc).__name__}: {exc}")

print()
print("--- stage 4: does resolving session-bound urls complete? ---")
started = time.monotonic()
try:
    resolved = ehentai.resolve_public_image_urls(display[:3], COOKIES, workers=3, timeout=60)
    print(f"  ok ({time.monotonic() - started:.1f}s): {len(resolved)} urls back")
except Exception as exc:
    print(f"  FAILED ({time.monotonic() - started:.1f}s): {type(exc).__name__}: {exc}")

print()
print("  all stages completed")
PY
    echo
    echo "--- exit: $? ---"
} > "$OUT" 2>&1

echo "written to $OUT"

#!/data/data/com.termux/files/usr/bin/bash
# Run the path the bot actually runs, and check what ends up on R2.
#
# "All images go into R2" is only true if host_on_r2 is reached on the real flow and every image
# comes back with a public URL. This calls the same functions in the same order - sweep, resolve,
# host - and then reads a Telegraph page back to see what it embeds.
#
# The sweep is capped with max_images so this finishes quickly while still exercising every step
# including the upload and the cache write.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
OUT="$HOME/twitter_pixiv_tg_bot/data/r2-e2e.txt"
cd "$HOME/twitter_pixiv_tg_bot/bot" || exit 1

set -a
while IFS= read -r line; do
    case "$line" in
        R2_*|BOT_TOKEN) eval "export $line" 2>/dev/null || true ;;
    esac
done < "$HOME/twitter_pixiv_tg_bot/.env"
set +a

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo

    timeout 420 python - <<'PY'
import asyncio
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, ".")
sys.path.insert(0, "vendor")

import httpx
import bot
import ehentai
import r2

URL = "https://e-hentai.org/g/2783744/3ec7dfe53d"
COOKIES = Path("../cookies/ehentai.txt")
LIMIT = 6

settings = r2.r2_settings()
print(f"--- settings ---")
print(f"  {settings.describe() if settings else 'R2 NOT CONFIGURED'}")
print(f"  cache file: {bot.PARSE_CACHE.path}")
print(f"  cache entries at start: {len(bot.PARSE_CACHE.entries)}")
print()

if settings is None:
    print("  cannot test without R2")
    raise SystemExit(1)

print(f"--- the gallery ---")
gallery = ehentai.fetch_gallery(URL, cookies_path=COOKIES, timeout=60)
print(f"  {gallery.title[:60]!r}  ({gallery.filecount} pages)")
print()

print(f"--- step 1: sweep {LIMIT} pages ---")
started = time.monotonic()
display, original = ehentai.fetch_gallery_images(
    URL, cookies_path=COOKIES, workers=6, timeout=60, max_images=LIMIT)
print(f"  {len(display)} display, {len(original)} original  "
      f"({time.monotonic() - started:.1f}s)")
if not display:
    print("  the sweep returned nothing")
    raise SystemExit(1)
print()

print("--- step 2: resolve to public urls (public_embed_urls does this) ---")
import inspect
# public_embed_urls needs a status object for its progress edits; a stub is enough here and keeps
# this from touching Telegram.
class Status:
    async def edit_text(self, *a, **k):
        return True
status = Status()

async def resolve():
    return await bot.public_embed_urls(display, gallery, status, report=True)

resolved = asyncio.run(resolve())
print(f"  {len(resolved)} urls back")
print()

print("--- step 3: host on R2 (host_on_r2, exactly as the bot calls it) ---")
async def host():
    return await bot.host_on_r2(resolved, gallery, "view", status)

started = time.monotonic()
hosted = asyncio.run(host())
elapsed = time.monotonic() - started
print(f"  {len(hosted)} urls back  ({elapsed:.1f}s)")
print()

on_r2 = [u for u in hosted if u.startswith(settings.public_base.rstrip("/"))]
print(f"--- how many are on R2 ---")
print(f"  {len(on_r2)}/{len(hosted)}")
for url in hosted[:3]:
    print(f"    {url}")
if len(on_r2) != len(hosted):
    print()
    print("  *** not all of them are on R2 ***")
    for url in hosted:
        if not url.startswith(settings.public_base.rstrip("/")):
            print(f"    still original: {url[:100]}")
print()

print("--- anonymous fetch of each, which is what a reader does ---")
good = 0
with httpx.Client(timeout=40, follow_redirects=True) as http:
    for url in hosted:
        try:
            response = http.get(url)
            ct = (response.headers.get("content-type") or "").split(";")[0]
            if response.status_code == 200 and ct.startswith("image/"):
                good += 1
            else:
                print(f"    {response.status_code} {ct}  {url[-50:]}")
        except Exception as exc:
            print(f"    FAILED {type(exc).__name__}  {url[-50:]}")
print(f"  {good}/{len(hosted)} served as images")
print()

print("--- was it recorded in the cache? ---")
recorded = bot.cached_r2_urls(gallery.page_url, gallery, "view")
print(f"  cached R2 urls for 'view': {len(recorded)}")
print(f"  matches what was returned: {recorded == hosted}")
print()

print("--- and a second call must not re-upload ---")
started = time.monotonic()
again = asyncio.run(host())
print(f"  {len(again)} urls  ({time.monotonic() - started:.2f}s)")
print(f"  identical: {again == hosted}")
print()

print("--- the bucket now holds ---")
client = r2._make_client(settings, 30)
total = 0
token = None
while True:
    kwargs = {"Bucket": settings.bucket, "Prefix": "galleries/"}
    if token:
        kwargs["ContinuationToken"] = token
    page = client.list_objects_v2(**kwargs)
    total += page.get("KeyCount", 0)
    if not page.get("IsTruncated"):
        break
    token = page.get("NextContinuationToken")
print(f"  {total} objects under galleries/")
print()

print("--- cleaning up this run's objects ---")
removed = 0
for url in hosted:
    key = url.split(f"{settings.public_base.rstrip('/')}/", 1)[-1]
    try:
        client.delete_object(Bucket=settings.bucket, Key=key)
        removed += 1
    except Exception as exc:
        print(f"    could not delete {key}: {exc}")
print(f"  removed {removed}")
# And the cache entry this wrote, so a later real parse is not served a stale list.
try:
    if Path(bot.PARSE_CACHE.path).exists():
        Path(bot.PARSE_CACHE.path).unlink()
    print("  and the cache file, so nothing points at the deleted objects")
except OSError as exc:
    print(f"  cache file: {exc}")
PY
    echo
    echo "--- exit: $? ---"
} > "$OUT" 2>&1

echo "written to $OUT"

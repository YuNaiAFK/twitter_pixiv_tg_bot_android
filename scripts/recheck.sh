#!/data/data/com.termux/files/usr/bin/bash
# The page embeds 205 img.ginka.uk urls. Do they still load, some twenty hours later?
#
# That is the whole question behind "the images still break after a while". If they load, the expiry
# problem is solved and what broke is something else - the page being removed, a client cache, or a
# different page. If they do not, then a stable URL was not enough and the reason matters.
#
# Checks the page's own current HTML rather than the recorded list, so a page edited since the upload
# is seen as it is now, and samples across the range rather than from the front.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
OUT="$HOME/twitter_pixiv_tg_bot/data/recheck.txt"
cd "$HOME/twitter_pixiv_tg_bot/bot" || exit 1

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo

    python - <<'PY'
import re
import sys
import time
from collections import Counter

import httpx

sys.path.insert(0, ".")
sys.path.insert(0, "vendor")

PAGE = "Mutou-Mato-Utsushiyo-to-Osanaduma-Chinese-Decensored-Digital-10-16-9"
PAGE_URL = f"https://telegra.ph/{PAGE}"

print(f"--- is the page still there? ---")
with httpx.Client(timeout=30, follow_redirects=True) as http:
    response = http.get(PAGE_URL)
print(f"  {PAGE_URL}")
print(f"  HTTP {response.status_code}")
if response.status_code != 200:
    print("  the page itself is gone - that is Telegraph removing it, not an image problem")
    raise SystemExit(0)
html = response.text
print(f"  {len(html)} bytes of HTML")
print()

images = re.findall(r'<img\b[^>]*?\bsrc=["\']([^"\']+)["\']', html, re.I)
print(f"--- it embeds {len(images)} images ---")
hosts = Counter(re.match(r"https?://([^/]+)", u).group(1) for u in images if re.match(r"https?://([^/]+)", u))
for host, count in hosts.most_common():
    print(f"  {host:40} {count}")
print()

if not images:
    print("  no images in the page at all")
    raise SystemExit(0)

# Spread across the list: a page whose later images broke is not called healthy by its first three.
step = max(1, len(images) // 12)
sample = [images[i] for i in range(0, len(images), step)][:12]

print(f"--- fetching {len(sample)} of them, spread across the page ---")
ok = 0
for url in sample:
    try:
        with httpx.Client(timeout=40, follow_redirects=True) as http:
            got = http.get(url)
        content_type = (got.headers.get("content-type") or "").split(";")[0]
        good = got.status_code == 200 and content_type.startswith("image/")
        ok += 1 if good else 0
        print(f"  {got.status_code}  {content_type:12} {len(got.content):>8} bytes  {url[-52:]}")
    except Exception as exc:
        print(f"  FAILED {type(exc).__name__}: {url[-52:]}")
print()
print(f"  {ok}/{len(sample)} loaded as images")
print()

# And how old the objects are, which says whether anything is pruning them.
print("--- the objects' age, from the bucket ---")
import r2
settings = r2.r2_settings()
if settings:
    client = r2._make_client(settings, 30)
    listing = client.list_objects_v2(Bucket=settings.bucket, Prefix="galleries/", MaxKeys=5)
    for item in listing.get("Contents", []):
        age = (time.time() - item["LastModified"].timestamp()) / 3600
        print(f"  {age:6.1f}h old  {item['Size']:>8} bytes  {item['Key'][-46:]}")
    print()
    print("  R2 has no expiry of its own; objects persist until deleted or a lifecycle rule removes")
    print("  them. A lifecycle rule on this bucket would explain images disappearing over time.")
PY
} > "$OUT" 2>&1

echo "written to $OUT"

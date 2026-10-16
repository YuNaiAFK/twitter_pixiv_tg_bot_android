#!/data/data/com.termux/files/usr/bin/bash
# Read a real Telegraph page's image URLs and check them, in the domain the bot runs in.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
OUT="$HOME/twitter_pixiv_tg_bot/data/page-image-result.txt"
cd "$HOME/twitter_pixiv_tg_bot/bot" || exit 1

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S')  domain: $(cat /proc/self/attr/current 2>/dev/null) ==="
    python - <<'PY'
import sys
import time

sys.path.insert(0, ".")
sys.path.insert(0, "vendor")

import ehentai

# Build a page whose images point at hosts that will and will not answer, so both directions of the
# check are exercised - a check that only ever says "broken" is not a check.
page = ehentai.create_telegraph_page(
    ehentai.EhentaiGallery(url="u", gid="1", token="t", title="image check probe", tags={}),
    [
        "https://telegra.ph/favicon.ico",              # real, reachable, but not an image type we accept
        "https://example.invalid/missing.jpg",         # cannot resolve
    ],
    author_name="probe",
)
print(f"  page: {page.url}")

print()
print("=== the page's own <img> urls, read back ===")
images = ehentai.telegraph_page_images(page.path)
print(f"  found {len(images)}")
for u in images[:6]:
    print(f"    {u[:100]}")

print()
print("=== checking them ===")
started = time.monotonic()
report = ehentai.check_image_urls(images, workers=6, timeout=20)
print(f"  {report.summary()}   ({time.monotonic() - started:.1f}s)")
for b in report.broken[:6]:
    print(f"    {b.reason:22} {b.url[:70]}")

print()
print("=== early stop: one broken is enough ===")
started = time.monotonic()
early = ehentai.check_image_urls(images * 30, workers=16, timeout=20, stop_after=1)
print(f"  {early.summary()}   ({time.monotonic() - started:.1f}s)")

print()
print("=== a page that does not exist ===")
print(f"  images found: {len(ehentai.telegraph_page_images('this-page-does-not-exist-9999'))}")
PY
} > "$OUT" 2>&1
echo "written to $OUT"

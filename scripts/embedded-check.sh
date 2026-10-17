#!/data/data/com.termux/files/usr/bin/bash
# What is actually embedded in the pages the bot produced?
#
# "The images still break after a while" has a small number of causes and they are distinguishable:
#
#   - the page still embeds hath.network links, so nothing was gained. Either the R2 wiring never ran
#     for that gallery, or the page predates it - a page is only rewritten when it is regenerated.
#   - the page embeds img.ginka.uk links and they fail, which is an R2 or domain problem rather than
#     an expiry one.
#   - the page embeds img.ginka.uk links and they work, and what broke is something else.
#
# So this reads each recorded page and asks its own HTML what it contains, then counts the hosts.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
OUT="$HOME/twitter_pixiv_tg_bot/data/embedded-check.txt"
cd "$HOME/twitter_pixiv_tg_bot/bot" || exit 1

set -a
while IFS= read -r line; do
    case "$line" in
        R2_*) eval "export $line" 2>/dev/null || true ;;
    esac
done < "$HOME/twitter_pixiv_tg_bot/.env"
set +a

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo

    python - <<'PY'
import json
import re
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, ".")
sys.path.insert(0, "vendor")

import httpx

# ---------------------------------------------------------------- the cache
path = None
for name in ("parse_cache.json", "../parse_cache.json"):
    if Path(name).is_file():
        path = Path(name)
        break

print(f"--- cache: {path} ---")
data = json.loads(path.read_text(encoding="utf-8"))
print(f"  entries: {len(data)}")
print()

with_r2 = []
with_telegraph = []
for key, value in data.items():
    payload = (value or {}).get("payload") or {}
    if payload.get("r2"):
        modes = {m: len(u or []) for m, u in payload["r2"].items()}
        with_r2.append((key, modes))
    if payload.get("telegraph"):
        with_telegraph.append((key, payload.get("telegraph")))

print(f"--- galleries with recorded R2 urls: {len(with_r2)} ---")
for key, modes in with_r2[:10]:
    print(f"  {key[-40:]:42} {modes}")
if not with_r2:
    print("  (none - the R2 upload has never completed for any gallery)")
print()

print(f"--- galleries with a recorded Telegraph page: {len(with_telegraph)} ---")
for key, pages in with_telegraph[:10]:
    for mode, entry in (pages or {}).items():
        print(f"  {key[-30:]:32} {mode:5} {entry.get('url', '')}")
print()

# ---------------------------------------------------------------- what the pages embed
print("--- what each page's own HTML contains ---")
hosts = Counter()
pages_checked = 0
for key, pages in with_telegraph[:6]:
    for mode, entry in (pages or {}).items():
        url = entry.get("url") or ""
        page_path = entry.get("path") or ""
        if not page_path:
            continue
        try:
            with httpx.Client(timeout=30, follow_redirects=True) as http:
                html = http.get(f"https://telegra.ph/{page_path}").text
        except Exception as exc:
            print(f"  {mode:5} could not read {page_path}: {type(exc).__name__}")
            continue
        pages_checked += 1
        found = re.findall(r'<img\b[^>]*?\bsrc=["\']([^"\']+)["\']', html, re.I)
        page_hosts = Counter()
        for src in found:
            match = re.match(r"https?://([^/]+)", src)
            page_hosts[match.group(1) if match else "?"] += 1
        hosts.update(page_hosts)
        print(f"  {mode:5} {page_path[:44]:46} {len(found)} imgs  {dict(page_hosts)}")

print()
print("--- totals across those pages ---")
for host, count in hosts.most_common():
    print(f"  {host:40} {count}")
if not hosts:
    print("  (no pages could be read)")
print()

# ---------------------------------------------------------------- is R2 itself healthy
print("--- the R2 bucket ---")
import r2
settings = r2.r2_settings()
if settings is None:
    print("  R2 is not configured")
else:
    print(f"  {settings.describe()}")
    try:
        client = r2._make_client(settings, 30)
        total = 0
        token = None
        sample = []
        while True:
            kwargs = {"Bucket": settings.bucket, "Prefix": "galleries/"}
            if token:
                kwargs["ContinuationToken"] = token
            page = client.list_objects_v2(**kwargs)
            for item in page.get("Contents", []):
                total += 1
                if len(sample) < 3:
                    sample.append(item["Key"])
            if not page.get("IsTruncated"):
                break
            token = page.get("NextContinuationToken")
        print(f"  objects under galleries/: {total}")
        for key in sample:
            print(f"    {key}")
        if total:
            # Anonymous fetch, which is what a reader's browser does.
            url = settings.public_url(sample[0])
            with httpx.Client(timeout=30, follow_redirects=True) as http:
                response = http.get(url)
            print(f"  anonymous fetch of the first: HTTP {response.status_code}  "
                  f"{len(response.content)} bytes")
    except Exception as exc:
        print(f"  FAILED: {type(exc).__name__}: {exc}")
PY
} > "$OUT" 2>&1

echo "written to $OUT"

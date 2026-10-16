#!/data/data/com.termux/files/usr/bin/bash
# Why are the cached display URLs answering 403 when the same kind of URL worked earlier?
#
# Two candidates, and they need different fixes in the caller:
#
#   expired keystamp   the signed links are time limited; the cache is three hours old. Nothing to do
#                      but re-sweep, which the bot already does.
#   session required   some e-hentai image hosts answer only when the request carries the e-hentai
#                      cookies and the right Referer. If that is it, the uploader has to be given
#                      both, and the sweep output cannot be used as-is.
#
# The keystamp value is printed as a timestamp as well as a number, which settles the first question
# directly instead of by inference.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"

PROJECT_DIR="$HOME/twitter_pixiv_tg_bot"
OUT="$PROJECT_DIR/data/hath-403.txt"
cd "$PROJECT_DIR/bot" || exit 1

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo "  now (unix): $(date +%s)"
    echo

    python - <<'PY'
import json
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, ".")
sys.path.insert(0, "vendor")

import httpx
import ehentai

urls = []
for name in ("parse_cache.json", "../parse_cache.json"):
    path = Path(name)
    if not path.is_file():
        continue
    data = json.loads(path.read_text(encoding="utf-8"))
    for value in data.values():
        payload = (value or {}).get("payload") or {}
        found = payload.get("display_urls") or []
        if found:
            urls.extend(found)
    if urls:
        print(f"  source: {name}, {len(urls)} urls")
        break

if not urls:
    print("  no cached urls")
    raise SystemExit(0)

now = int(time.time())
print()
print("--- what the keystamps say ---")
seen = set()
for url in urls[:40]:
    match = re.search(r"keystamp=(\d+)", url)
    if not match:
        continue
    stamp = int(match.group(1))
    if stamp in seen:
        continue
    seen.add(stamp)
    delta = stamp - now
    print(f"  {stamp}  {time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(stamp))}  "
          f"({delta:+d}s from now)")
    if len(seen) >= 4:
        break
print()

sample = urls[0]
host = httpx.URL(sample).host
print(f"--- the sample url ---")
print(f"  host: {host}")
print(f"  session-bound per ehentai.is_session_bound_image: "
      f"{ehentai.is_session_bound_image(sample)}")
print()

# The cookies the bot has for e-hentai, read the same way the bot reads them.
cookies = {}
cookie_path = None
for candidate in ("../cookies/ehentai.txt", "cookies/ehentai.txt"):
    if Path(candidate).is_file():
        cookie_path = candidate
        break
if cookie_path:
    for line in Path(cookie_path).read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) >= 7:
            cookies[parts[5]] = parts[6]
        elif "=" in line and " " not in line:
            k, _, v = line.partition("=")
            cookies[k.strip()] = v.strip()
    print(f"--- cookies from {cookie_path}: {len(cookies)} entries ---")
    print(f"  names: {', '.join(sorted(cookies)[:6])}")
else:
    print("--- no cookie file found ---")
print()

print("--- fetching the sample under four conditions ---")
variants = [
    ("bare",                     {}),
    ("Referer: e-hentai.org",    {"Referer": "https://e-hentai.org/"}),
    ("cookies",                  {"Cookie": "; ".join(f"{k}={v}" for k, v in cookies.items())} if cookies else {}),
    ("cookies + Referer",        {"Cookie": "; ".join(f"{k}={v}" for k, v in cookies.items()),
                                  "Referer": "https://e-hentai.org/"} if cookies else
                                 {"Referer": "https://e-hentai.org/"}),
]
with httpx.Client(timeout=30, follow_redirects=True) as http:
    for label, headers in variants:
        try:
            response = http.get(sample, headers=headers)
            ct = (response.headers.get("content-type") or "").split(";")[0]
            print(f"  {label:22} HTTP {response.status_code}  {ct:14} {len(response.content):>8} bytes")
        except Exception as exc:
            print(f"  {label:22} FAILED {type(exc).__name__}: {exc}")
print()

print("--- and whether a *freshly* resolved public url behaves differently ---")
try:
    resolved = ehentai.resolve_public_image_urls([sample], "../cookies/ehentai.txt")
    new = resolved[0] if resolved else ""
    print(f"  resolved: {'same as the cached one' if new == sample else 'a different url'}")
    if new and new != sample:
        with httpx.Client(timeout=30, follow_redirects=True) as http:
            response = http.get(new)
        print(f"  fetching it: HTTP {response.status_code}  {len(response.content)} bytes")
except Exception as exc:
    print(f"  resolve failed: {type(exc).__name__}: {exc}")
PY
} > "$OUT" 2>&1

echo "written to $OUT"

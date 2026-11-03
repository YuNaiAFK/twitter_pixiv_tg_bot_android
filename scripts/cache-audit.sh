#!/data/data/com.termux/files/usr/bin/bash
# What is actually in the cache, and which flows put it there?
#
# The operator's request was "本子走的是r2，不需要本地快取" - galleries go through R2, so no local cache.
# That is true of the gallery *images* (they stream to R2 without touching disk), but the 247 MB on
# disk may not be gallery data at all. This counts by kind before anything is deleted, because
# removing the wrong half either loses the archive cache (a 200 MB re-download) or keeps 150 MB of
# Twitter media the operator wanted gone.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
OUT="$HOME/twitter_pixiv_tg_bot/data/cache-audit.txt"
PROJECT="$HOME/twitter_pixiv_tg_bot"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo

    echo "--- sizes on disk ---"
    du -sh "$PROJECT/.cache" 2>/dev/null | sed 's/^/  /'
    du -sh "$PROJECT/.cache/archives" 2>/dev/null | sed 's/^/  /'
    echo "  loose files: $(find "$PROJECT/.cache" -maxdepth 1 -type f 2>/dev/null | wc -l)"
    echo "  archive files: $(find "$PROJECT/.cache/archives" -type f 2>/dev/null | wc -l)"
    echo

    echo "--- what the parse cache indexes, by kind ---"
    python - <<'PY'
import json
from collections import Counter
from pathlib import Path

path = Path.home() / "twitter_pixiv_tg_bot" / "parse_cache.json"
try:
    data = json.loads(path.read_text(encoding="utf-8"))
except Exception as exc:
    print(f"  cannot read: {type(exc).__name__}: {exc}")
    raise SystemExit(0)

entries = data.get("entries") or {}
kinds = Counter()
media_hosts = Counter()
gallery_urls = 0
for key, value in entries.items():
    kind = (value or {}).get("kind") or "?"
    kinds[kind] += 1
    if kind == "media":
        # The key is the URL for a media entry.
        host = key.split("/")[2] if key.count("/") >= 2 else key
        media_hosts[host] += 1
    elif kind == "gallery":
        gallery_urls += 1

print(f"  entries: {len(entries)}")
for kind, count in kinds.most_common():
    print(f"    {kind:10} {count}")
print()
print("  media entries by host:")
for host, count in media_hosts.most_common(8):
    print(f"    {host:34} {count}")
print()
print(f"  gallery entries: {gallery_urls}  (these are the e-hentai ones)")
print()

files = sum(len((v or {}).get("files") or []) for v in entries.values()
            if (v or {}).get("kind") == "media")
print(f"  file names referenced by media entries: {files}")
PY
    echo

    echo "--- the archive cache: whose archives, and how big ---"
    if [ -d "$PROJECT/.cache/archives" ]; then
        find "$PROJECT/.cache/archives" -type f -printf '    %s  %f\n' 2>/dev/null \
            | sort -rn | head -8
        echo "    total: $(du -sh "$PROJECT/.cache/archives" 2>/dev/null | cut -f1)"
    else
        echo "    none"
    fi
    echo

    echo "--- do gallery parses write page files to disk at all? ---"
    # host_on_r2 fetches each image into memory and uploads it; nothing is written under .cache for
    # a Telegraph parse. The archive path is the only e-hentai thing that touches disk.
    count=0
    for f in "$PROJECT/.cache"/*; do
        [ -f "$f" ] || continue
        count=$((count + 1))
    done
    echo "  loose files: $count (from media parses, named <urlhash>_<n><ext>)"
    echo
    echo "--- settings that control this ---"
    grep -E "^(CACHE_DIR|CACHE_STALE_SECONDS|CACHE_MAX_ENTRIES|ARCHIVE_CACHE|ARCHIVE_CACHE_MAX_BYTES|GALLERY_META_TTL_SECONDS)=" \
        "$PROJECT/.env" 2>/dev/null | sed 's/^/  /'
} > "$OUT" 2>&1

echo "written to $OUT"

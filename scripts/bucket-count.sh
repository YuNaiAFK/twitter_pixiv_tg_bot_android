#!/data/data/com.termux/files/usr/bin/bash
# Is the upload actually progressing?
#
# The log went quiet after the sweep started and stayed quiet, which looks like a hang and is
# probably not one: host_on_r2 logs nothing while it uploads, so a gallery in the middle of a
# multi-minute upload produces exactly this silence. The bucket is the thing that can tell the
# difference between working and stuck, because it changes while the upload runs.
#
# Counts twice, 20 seconds apart, so an increase is visible rather than inferred.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
OUT="$HOME/twitter_pixiv_tg_bot/data/bucket-count.txt"

set -a
while IFS= read -r line; do
    case "$line" in
        R2_*) eval "export $line" 2>/dev/null || true ;;
    esac
done < "$HOME/twitter_pixiv_tg_bot/.env"
set +a

cd "$HOME/twitter_pixiv_tg_bot/bot" || exit 1

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    python - <<'PY'
import os
import sys
import time

sys.path.insert(0, ".")
sys.path.insert(0, "vendor")

import r2

settings = r2.r2_settings()
print(f"  {settings.describe()}")
client = r2._make_client(settings, 30)

def count():
    total = 0
    token = None
    while True:
        kwargs = {"Bucket": settings.bucket, "Prefix": "galleries/"}
        if token:
            kwargs["ContinuationToken"] = token
        page = client.list_objects_v2(**kwargs)
        total += page.get("KeyCount", 0)
        if not page.get("IsTruncated"):
            return total
        token = page.get("NextContinuationToken")

first = count()
print(f"  objects now: {first}")

# The bot logs nothing during an upload, so this is the only progress signal available.
time.sleep(20)
second = count()
print(f"  objects 20s later: {second}")
print()
if second > first:
    print(f"  RESULT: progressing - {second - first} objects added in 20s "
          f"(about {(second - first) * 3} per minute)")
elif second == first and first > 0:
    print("  RESULT: unchanged - either finished, or stalled")
else:
    print("  RESULT: nothing in the bucket yet")

# And what the log says, so the two views are side by side.
print()
print("--- the bot log's last 3 lines ---")
log = "/data/data/com.termux/files/home/twitter_pixiv_tg_bot/data/bot.log"
with open(log, encoding="utf-8", errors="replace") as handle:
    lines = handle.readlines()
for line in lines[-3:]:
    print("  " + line.rstrip())
print(f"  log mtime: {time.strftime('%H:%M:%S', time.localtime(os.path.getmtime(log)))}")
print(f"  now:       {time.strftime('%H:%M:%S')}")
PY
} > "$OUT" 2>&1

echo "written to $OUT"

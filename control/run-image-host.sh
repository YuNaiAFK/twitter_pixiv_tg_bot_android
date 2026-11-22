#!/data/data/com.termux/files/usr/bin/bash
set -eu
PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
DATA="$PROJECT/data"
PID="$DATA/image-host.pid"
ROOT="$DATA/public-images"
mkdir -p "$ROOT"
if [ -s "$PID" ] && kill -0 "$(cat "$PID")" 2>/dev/null; then
    echo "Image host already running"
    exit 0
fi
nohup python "$PROJECT/control/image_host.py" "$ROOT" >> "$DATA/image-host.log" 2>&1 </dev/null &
echo "$!" > "$PID"

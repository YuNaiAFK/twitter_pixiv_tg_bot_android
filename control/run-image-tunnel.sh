#!/data/data/com.termux/files/usr/bin/bash
set -eu
PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
DATA="$PROJECT/data"
TOKEN="$HOME/.phone-image-host.token"
test -s "$TOKEN" || { echo "缺少手機圖床隧道 token 檔案"; exit 1; }
mkdir -p "$DATA"
exec flock -n "$DATA/image-tunnel.lock" proot-distro login \
    --bind "$TOKEN:/tmp/phone-image-host.token" botapi -- \
    /usr/local/bin/cloudflared tunnel --no-autoupdate --protocol http2 \
    run --token-file /tmp/phone-image-host.token

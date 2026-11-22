#!/data/data/com.termux/files/usr/bin/bash
set -eu
PROJECT="$HOME/twitter_pixiv_tg_bot"
DATA="$PROJECT/data"
mkdir -p "$DATA"
bash "$PROJECT/control/run-image-host.sh" >> "$DATA/image-host-boot.log" 2>&1
nohup setsid bash "$PROJECT/control/run-image-tunnel.sh" \
    >> "$DATA/image-tunnel.log" 2>&1 </dev/null &

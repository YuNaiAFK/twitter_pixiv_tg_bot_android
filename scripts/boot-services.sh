#!/data/data/com.termux/files/usr/bin/bash
# What runs at boot: wait for the network, then hand over to start-all.sh.
#
# Install as an autostart script:
#
#   mkdir -p ~/.termux/boot
#   cp scripts/boot-services.sh ~/.termux/boot/10-bot.sh
#   chmod +x ~/.termux/boot/10-bot.sh
#
# With the Termux:Boot app, `~/.termux/boot/*.sh` runs at boot. The app has to be opened once
# after installation so Android registers it, and Termux plus the VPN app must both be exempt
# from battery optimisation or Android kills them.
#
# This script used to start the server and the bot itself. That logic now lives in
# scripts/start-all.sh, which also starts the control panel, and is the same script the phone app
# invokes over RUN_COMMAND. One implementation means a boot and a button press cannot drift apart.

set -u
export PATH="${PREFIX:-/data/data/com.termux/files/usr}/bin:${PREFIX:-/data/data/com.termux/files/usr}/bin/applets:$PATH"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$PROJECT_DIR/data/boot.log"

mkdir -p "$PROJECT_DIR/data"
log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG"; }

log "=== boot $(date) ==="

# A wake lock so Android does not suspend the CPU. Without it the server can be killed partway
# through a Telegram upload.
if command -v termux-wake-lock >/dev/null 2>&1; then
    termux-wake-lock 2>/dev/null && log "wake lock held" || log "wake lock failed"
fi

# Android may not have brought Wi-Fi up yet. The VPN has to be reachable before anything useful
# can happen - every download needs it, and the panel is useless without it - so wait rather
# than starting a bot that then fails every request.
log "waiting for the VPN on 10808…"
for i in $(seq 1 40); do
    if (exec 3<>/dev/tcp/127.0.0.1/10808) 2>/dev/null; then
        exec 3<&- 3>&- 2>/dev/null
        log "VPN is up after ${i} attempt(s)"
        break
    fi
    sleep 3
done

# start-all.sh orders the steps and waits for each; see its header for why the order matters.
log "handing over to start-all.sh"
bash "$PROJECT_DIR/scripts/start-all.sh" >> "$LOG" 2>&1
log "start-all.sh finished with $?"

log "done"

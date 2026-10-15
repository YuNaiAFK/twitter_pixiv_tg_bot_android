#!/data/data/com.termux/files/usr/bin/bash
# Start everything after a reboot: the self-hosted Bot API server, then the bot.
#
# **The order matters and both steps are required.** With TELEGRAM_LOCAL=1 the bot expects a
# local server; if the server is not up it either falls back to the public API with a 50 MB
# limit or fails to connect, depending on how the startup check resolves. Starting the server
# first and giving it time to bind is what makes a reboot come back to a working bot.
#
# Install as an autostart script:
#
#   pkg install termux-services          # or install the Termux:Boot app from F-Droid
#   mkdir -p ~/.termux/boot
#   cp scripts/boot-services.sh ~/.termux/boot/10-bot.sh
#   chmod +x ~/.termux/boot/10-bot.sh
#
# With the Termux:Boot app, ~/.termux/boot/*.sh runs at boot. The app has to be opened once after
# installation so Android registers it, and Termux itself must be exempt from battery
# optimisation or Android will kill both the app and this script.

set -u
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"

PROJ="$HOME/twitter_pixiv_tg_bot"
LOG="$PROJ/data/boot.log"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG"; }

{
    echo "=== boot $(date) ==="
} >> "$LOG"

cd "$PROJ" 2>/dev/null || { log "ERROR: $PROJ not found"; exit 1; }

# A wake lock so Android does not suspend the CPU; without it the server can be killed while
# Telegram is uploading.
if command -v termux-wake-lock >/dev/null 2>&1; then
    termux-wake-lock 2>/dev/null && log "wake lock held" || log "wake lock failed"
fi

# Android may not have brought Wi-Fi up yet at boot. The VPN has to be reachable before the bot
# can do anything useful, so wait for it rather than failing immediately.
log "waiting for the proxy..."
for i in $(seq 1 40); do
    if (exec 3<>/dev/tcp/127.0.0.1/10808) 2>/dev/null; then
        exec 3<&- 3>&- 2>/dev/null
        log "proxy is up after ${i}s"
        break
    fi
    sleep 3
done

log "starting the Bot API server"
bash scripts/run-server.sh start >> "$LOG" 2>&1 || log "server start failed"

# The server needs a moment to bind 8081 before the bot asks it anything.
for i in $(seq 1 20); do
    if (exec 3<>/dev/tcp/127.0.0.1/8081) 2>/dev/null; then
        exec 3<&- 3>&- 2>/dev/null
        log "server is listening after ${i}s"
        break
    fi
    sleep 2
done

log "starting the bot"
bash scripts/run-bot.sh --background >> "$LOG" 2>&1 || log "bot start failed"

log "done"

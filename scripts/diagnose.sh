#!/data/data/com.termux/files/usr/bin/bash
# Why is the bot not working?
#
# The log says the self-hosted Bot API server timed out. That is one symptom with several possible
# causes - the proot container died, the VPN is down so the container cannot reach Telegram, the
# binary was never started after a reboot, or the phone killed the container for memory. This walks
# the chain from the bottom up rather than guessing.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
OUT="$HOME/twitter_pixiv_tg_bot/data/diagnose.txt"
PROJECT="$HOME/twitter_pixiv_tg_bot"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo

    echo "--- uptime and load ---"
    uptime 2>&1 | sed 's/^/  /'
    echo

    echo "--- the processes that should be running ---"
    for name in bot.py panel.py telegram-bot-api proot; do
        found=$(ps -ef 2>/dev/null | grep -F "$name" | grep -v grep)
        if [ -n "$found" ]; then
            echo "  $name:"
            echo "$found" | head -3 | sed 's/^/    /'
        else
            echo "  $name: NOT RUNNING"
        fi
    done
    echo

    echo "--- listening ports (8081 = bot api, 8090 = panel) ---"
    for port in 8081 8090; do
        # TERMUX: ss is not always present; /proc/net/tcp needs the hex port. 0x1F91 = 8081.
        if command -v ss >/dev/null 2>&1; then
            line=$(ss -ltn 2>/dev/null | grep ":$port ")
            if [ -n "$line" ]; then echo "  $port: $line"; else echo "  $port: not listening"; fi
        else
            hex=$(printf '%04X' "$port")
            if grep -qi ":$hex " /proc/net/tcp /proc/net/tcp6 2>/dev/null; then
                echo "  $port: listening"
            else
                echo "  $port: not listening"
            fi
        fi
    done
    echo

    echo "--- can the bot's own port be reached at all ---"
    if command -v curl >/dev/null 2>&1; then
        curl -s -o /dev/null -w "  http://127.0.0.1:8081/bot<token>/getMe -> %{http_code} in %{time_total}s\n" \
            --max-time 5 "http://127.0.0.1:8081/" 2>&1 || echo "  curl failed"
        curl -s -o /dev/null -w "  http://127.0.0.1:8090/api/status -> %{http_code} in %{time_total}s\n" \
            --max-time 5 "http://127.0.0.1:8090/api/status" 2>&1 || echo "  curl failed"
    else
        echo "  curl not installed"
    fi
    echo

    echo "--- the VPN / proxy ---"
    if [ -f "$HOME/.proxy-url" ]; then
        echo "  ~/.proxy-url: $(cat "$HOME/.proxy-url")"
    else
        echo "  ~/.proxy-url: absent"
    fi
    ip -4 addr show 2>/dev/null | grep -E "tun|ppp" | sed 's/^/  tun: /'
    if command -v curl >/dev/null 2>&1; then
        proxy=$(cat "$HOME/.proxy-url" 2>/dev/null)
        if [ -n "$proxy" ]; then
            curl -s -o /dev/null -w "  api.telegram.org via proxy -> %{http_code} in %{time_total}s\n" \
                --max-time 8 -x "$proxy" "https://api.telegram.org/" 2>&1 || echo "  proxy request failed"
        fi
    fi
    echo

    echo "--- the proot container ---"
    if command -v proot-distro >/dev/null 2>&1; then
        proot-distro list 2>&1 | head -12 | sed 's/^/  /'
    else
        echo "  proot-distro not installed"
    fi
    ROOTFS="$PREFIX/var/lib/proot-distro/containers/botapi/rootfs"
    if [ -d "$ROOTFS" ]; then
        echo "  rootfs: exists ($(du -sh "$ROOTFS" 2>/dev/null | cut -f1))"
        BIN="$ROOTFS/usr/local/bin/telegram-bot-api"
        if [ -f "$BIN" ]; then
            echo "  binary: $(ls -la "$BIN" | awk '{print $5}') bytes"
        else
            echo "  binary: MISSING"
        fi
    else
        echo "  rootfs: MISSING"
    fi
    echo

    echo "--- the server's own log ---"
    for f in "$PROJECT/data/server.log" "$PROJECT/data/bot-api.log" "$PROJECT/data/telegram-bot-api.log"; do
        if [ -f "$f" ]; then
            echo "  $f ($(wc -c < "$f") bytes):"
            tail -20 "$f" | sed 's/^/    /'
            break
        fi
    done
    ls -la "$PROJECT/data/"*.log 2>/dev/null | sed 's/^/  /'
    echo

    echo "--- the panel ---"
    if [ -f "$PROJECT/data/panel.log" ]; then
        tail -15 "$PROJECT/data/panel.log" | sed 's/^/  /'
    fi
    echo

    echo "--- the pid files ---"
    for f in "$PROJECT/data/"*.pid; do
        [ -f "$f" ] || continue
        pid=$(cat "$f" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            echo "  $(basename "$f"): $pid (alive)"
        else
            echo "  $(basename "$f"): ${pid:-empty} (DEAD - stale file)"
        fi
    done
} > "$OUT" 2>&1

echo "written to $OUT"

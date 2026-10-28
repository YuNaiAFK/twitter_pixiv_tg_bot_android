#!/data/data/com.termux/files/usr/bin/bash
# Is the network usable now, and if so bring the bot back?
#
# The bot died at boot because get_me() timed out before the VPN was up, and python-telegram-bot's
# bootstrap retry loop gave up. Now that the tunnel is up, the question is whether the proxy port and
# Telegram are actually reachable - and only then is starting the bot worth doing. Starting it into a
# dead network is exactly how it died the first time.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
OUT="$HOME/twitter_pixiv_tg_bot/data/recover.txt"
PROJECT="$HOME/twitter_pixiv_tg_bot"
PROXY=$(cat "$HOME/.proxy-url" 2>/dev/null)

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo

    echo "--- the proxy port ---"
    addr=${PROXY#*://}; h=${addr%%:*}; p=${addr##*:}
    if timeout 5 bash -c "exec 3<>/dev/tcp/${h}/${p}" 2>/dev/null; then
        echo "  ${h}:${p} OPEN"
        proxy_ok=1
    else
        echo "  ${h}:${p} CLOSED"
        proxy_ok=0
    fi
    echo

    echo "--- can Telegram be reached through it ---"
    if [ "$proxy_ok" = "1" ]; then
        code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 12 -x "$PROXY" \
               "https://api.telegram.org/" 2>/dev/null)
        echo "  https://api.telegram.org via proxy -> ${code:-failed}"
    else
        echo "  skipped: no proxy"
        code=000
    fi
    echo

    echo "--- the Bot API server ---"
    if timeout 5 bash -c "exec 3<>/dev/tcp/127.0.0.1/8081" 2>/dev/null; then
        echo "  :8081 OPEN"
    else
        echo "  :8081 CLOSED"
    fi
    echo

    if [ "$proxy_ok" != "1" ]; then
        echo "STOPPING: the VPN is not listening, so starting the bot would just kill it again."
        exit 0
    fi

    echo "--- starting the bot ---"
    bash "$PROJECT/scripts/run-bot.sh" --background 2>&1 | sed 's/^/  /'
    echo

    echo "--- waiting up to 60 s for it to come up ---"
    for i in $(seq 1 20); do
        sleep 3
        pid=$(cat "$PROJECT/data/bot.pid" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            # A live process is not the same as a working one: it can still be retrying Telegram.
            if tail -5 "$PROJECT/data/bot.log" 2>/dev/null | grep -q "Application started"; then
                echo "  up after $((i * 3))s, pid $pid"
                break
            fi
        else
            echo "  pid file says ${pid:-nothing} and it is not alive - it died"
            echo "  last log lines:"
            tail -12 "$PROJECT/data/bot.log" 2>/dev/null | sed 's/^/    /'
            exit 1
        fi
        [ "$i" = "20" ] && echo "  still starting after 60s (pid ${pid:-?})"
    done
    echo

    echo "--- final state ---"
    bash "$PROJECT/scripts/start-all.sh" --status 2>&1 | sed 's/^/  /'
    echo
    echo "--- the log's last lines ---"
    tail -6 "$PROJECT/data/bot.log" 2>/dev/null | sed 's/^/  /'
} > "$OUT" 2>&1

echo "written to $OUT"

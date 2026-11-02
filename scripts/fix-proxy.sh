#!/data/data/com.termux/files/usr/bin/bash
# Stop pointing the bot at a proxy that is not listening.
#
# v2rayNG is in TUN mode: tun0 carries everything, and nothing listens on 127.0.0.1:10808. The bot has
# BOT_PROXY set to that port, so every download fails with "Connection refused" on a network that
# works fine without it. That is worse than having no proxy configured - a closed port fails every
# request, while no proxy at all succeeds.
#
# Nothing is deleted. ~/.proxy-url is moved aside and the .env line is commented out, because the
# reverse change (turning v2rayNG back to proxy mode) needs the same value again, and retyping a URL
# from memory is how a working setup gets broken a second time.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
OUT="$HOME/twitter_pixiv_tg_bot/data/fix-proxy.txt"
PROJECT="$HOME/twitter_pixiv_tg_bot"
STAMP=$(date '+%Y%m%d-%H%M%S')

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo

    echo "--- before ---"
    echo "  ~/.proxy-url:   $(cat "$HOME/.proxy-url" 2>/dev/null || echo '(absent)')"
    grep -n '^BOT_PROXY=' "$PROJECT/.env" 2>/dev/null | sed 's/^/  /' || echo "  BOT_PROXY: not set"
    echo

    echo "--- is the port actually closed (confirm before acting) ---"
    PROXY=$(cat "$HOME/.proxy-url" 2>/dev/null)
    addr=${PROXY#*://}; h=${addr%%:*}; p=${addr##*:}
    if timeout 3 bash -c "exec 3<>/dev/tcp/${h}/${p}" 2>/dev/null; then
        echo "  ${h}:${p} is OPEN - not touching anything"
        exit 0
    fi
    echo "  ${h}:${p} is CLOSED"

    echo "--- does direct work (the thing the proxy is breaking) ---"
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 12 --noproxy '*' \
           "https://e-hentai.org/" 2>/dev/null)
    echo "  https://e-hentai.org/ direct -> ${code:-failed}"
    if [ -z "$code" ] || [ "$code" = "000" ]; then
        echo "  direct does not work either - the VPN is down, not misconfigured. Fixing nothing."
        exit 0
    fi
    echo

    echo "--- moving ~/.proxy-url aside ---"
    if [ -f "$HOME/.proxy-url" ]; then
        mv "$HOME/.proxy-url" "$HOME/.proxy-url.disabled-$STAMP"
        echo "  moved to ~/.proxy-url.disabled-$STAMP"
    else
        echo "  already absent"
    fi
    # The SOCKS form is kept by setup-termux.sh; it is equally wrong in TUN mode.
    for f in "$HOME/.proxy-url-socks"; do
        [ -f "$f" ] && mv "$f" "$f.disabled-$STAMP" && echo "  moved $(basename "$f") aside"
    done
    echo

    echo "--- commenting out BOT_PROXY in .env ---"
    if grep -q '^BOT_PROXY=' "$PROJECT/.env" 2>/dev/null; then
        cp "$PROJECT/.env" "$PROJECT/.env.bak-$STAMP"
        sed -i "s|^BOT_PROXY=|# BOT_PROXY=|" "$PROJECT/.env"
        echo "  commented out (backup: .env.bak-$STAMP)"
        grep -n 'BOT_PROXY' "$PROJECT/.env" | sed 's/^/  /'
    else
        echo "  already commented out"
    fi
    echo

    echo "--- the apt proxy file, if it points at the dead port ---"
    APT_PROXY="$PREFIX/etc/apt/apt.conf.d/95proxy"
    if [ -f "$APT_PROXY" ]; then
        cat "$APT_PROXY" | sed 's/^/  /'
        if grep -q "10808" "$APT_PROXY" 2>/dev/null; then
            cp "$APT_PROXY" "$APT_PROXY.bak-$STAMP"
            # Commented rather than deleted: apt without a proxy is correct in TUN mode, and the file
            # is the first thing anyone looks at when apt breaks.
            sed -i 's|^\(.*10808.*\)$|// \1|' "$APT_PROXY"
            echo "  commented out (backup: 95proxy.bak-$STAMP)"
        fi
    else
        echo "  no apt proxy file"
    fi
    echo

    echo "--- restarting the bot so it picks up the change ---"
    bash "$PROJECT/scripts/run-bot.sh" --stop 2>&1 | tail -3 | sed 's/^/  /'
    sleep 2
    bash "$PROJECT/scripts/run-bot.sh" --background 2>&1 | tail -6 | sed 's/^/  /'
    echo

    echo "--- waiting for it to come up ---"
    for i in $(seq 1 15); do
        sleep 3
        pid=$(cat "$PROJECT/data/bot.pid" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            if tail -4 "$PROJECT/data/bot.log" 2>/dev/null | grep -q "Application started"; then
                echo "  up after $((i * 3))s, pid $pid"
                break
            fi
        else
            echo "  it died; last log lines:"
            tail -12 "$PROJECT/data/bot.log" | sed 's/^/    /'
            exit 1
        fi
    done
    echo

    echo "--- now: does a real download work ---"
    # The exact call that was failing: gallery-dl against an X status, with the bot's own environment.
    bash "$PROJECT/scripts/run-bot.sh" --status 2>&1 | sed 's/^/  /'
    echo
    echo "  last log lines:"
    tail -5 "$PROJECT/data/bot.log" | sed 's/^/    /'
} > "$OUT" 2>&1

echo "written to $OUT"

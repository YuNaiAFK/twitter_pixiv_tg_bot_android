#!/data/data/com.termux/files/usr/bin/bash
# What is supposed to start at boot, and what is actually running now?
#
# The phone rebooted five minutes before the first diagnostic, so "the bot is not running" has two
# very different possible causes: the boot hook never fired, or it fired before the VPN was up and
# everything that needs the network failed. Those need different fixes.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
OUT="$HOME/twitter_pixiv_tg_bot/data/boot-check.txt"
PROJECT="$HOME/twitter_pixiv_tg_bot"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo

    echo "--- boot hook ---"
    if [ -d "$HOME/.termux/boot" ]; then
        echo "  ~/.termux/boot/ exists:"
        ls -la "$HOME/.termux/boot/" | sed 's/^/    /'
    else
        echo "  ~/.termux/boot/ DOES NOT EXIST - Termux:Boot will run nothing"
    fi
    echo

    echo "--- is Termux:Boot installed ---"
    pm list packages 2>/dev/null | grep -iE "termux.boot|termux.api|termux$" | sed 's/^/  /'
    echo

    echo "--- the boot script's own log, if it wrote one ---"
    for f in "$PROJECT/data/boot.log" "$PROJECT/data/start-all.log"; do
        if [ -f "$f" ]; then
            echo "  $f ($(wc -c < "$f") bytes, last line $(date -r "$f" '+%m-%d %H:%M')):"
            tail -25 "$f" | sed 's/^/    /'
            echo
        fi
    done
    echo

    echo "--- the VPN: is the port open right now ---"
    PROXY=$(cat "$HOME/.proxy-url" 2>/dev/null)
    echo "  configured: ${PROXY:-none}"
    host=${PROXY#*://}; host=${host%%:*}; port=${host##*:}
    if [ -n "$PROXY" ]; then
        # The last two colon-separated fields of the proxy URL are host:port.
        addr=$(echo "$PROXY" | sed 's|.*://||')
        h=${addr%%:*}; p=${addr##*:}
        echo "  testing ${h}:${p}"
        timeout 3 bash -c "cat < /dev/null > /dev/tcp/${h}/${p}" 2>/dev/null \
            && echo "  port ${p}: OPEN" || echo "  port ${p}: CLOSED (the VPN is not running)"
    fi
    echo

    echo "--- is the VPN app even installed and running ---"
    pm list packages 2>/dev/null | grep -iE "v2ray|clash|singbox|shadow" | sed 's/^/  installed: /'
    dumpsys activity services 2>/dev/null | grep -iE "v2ray|clash|tun" | head -5 | sed 's/^/  /'
    echo

    echo "--- tun interface ---"
    ip -4 addr show 2>/dev/null | grep -E "^[0-9]+: (tun|ppp)" | sed 's/^/  /'
    echo "  (no tun line above means the VPN's tunnel is not up)"
    echo

    echo "--- what started, in order, since boot ---"
    if [ -f "$PROJECT/scripts/start-all.sh" ]; then
        echo "  scripts/start-all.sh --status:"
        timeout 30 bash "$PROJECT/scripts/start-all.sh" --status 2>&1 | sed 's/^/    /'
    fi
    echo

    echo "--- can Telegram be reached at all right now ---"
    if command -v curl >/dev/null 2>&1; then
        curl -s -o /dev/null -w "  api.telegram.org direct  -> %{http_code} in %{time_total}s\n" \
            --max-time 6 "https://api.telegram.org/" 2>&1 || echo "  direct: failed"
        if [ -n "$PROXY" ]; then
            curl -s -o /dev/null -w "  api.telegram.org via proxy -> %{http_code} in %{time_total}s\n" \
                --max-time 8 -x "$PROXY" "https://api.telegram.org/" 2>&1 || echo "  proxy: failed"
        fi
    fi
} > "$OUT" 2>&1

echo "written to $OUT"

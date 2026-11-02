#!/data/data/com.termux/files/usr/bin/bash
# Is the tunnel actually carrying traffic, and is the configured proxy the right one?
#
# v2rayNG has two modes and they need opposite configuration:
#
#   TUN/VPN mode  - every packet is redirected by the tun interface. A BOT_PROXY pointing at a local
#                   port does not just fail, it *breaks* a working setup, because the process then
#                   tries a port nobody is listening on.
#   proxy mode    - nothing is redirected, and every tool must be told about the listening port.
#
# The port being closed while tun0 is up means the first case, and the fix is to remove the proxy
# setting rather than to add one. This proves which case it is instead of inferring it.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
OUT="$HOME/twitter_pixiv_tg_bot/data/network-mode.txt"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo

    echo "--- what the project thinks the proxy is ---"
    echo "  ~/.proxy-url:    $(cat "$HOME/.proxy-url" 2>/dev/null || echo '(absent)')"
    echo "  .env BOT_PROXY:  $(grep -m1 '^BOT_PROXY=' "$HOME/twitter_pixiv_tg_bot/.env" 2>/dev/null || echo '(not set)')"
    echo "  env HTTP_PROXY:  ${HTTP_PROXY:-(unset)}"
    echo "  env ALL_PROXY:   ${ALL_PROXY:-(unset)}"
    echo

    echo "--- the tun interface ---"
    ip -4 addr show 2>/dev/null | grep -A1 "tun" | sed 's/^/  /'
    echo "  default route:"
    ip route 2>/dev/null | grep -E "^default" | sed 's/^/    /'
    echo

    echo "--- direct connection, NO proxy: is the tunnel carrying traffic ---"
    for target in "https://api.telegram.org/" "https://e-hentai.org/" "https://www.google.com/"; do
        code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 12 --noproxy '*' \
               "$target" 2>/dev/null)
        printf '  %-30s -> %s\n' "$target" "${code:-failed}"
    done
    echo

    echo "--- through the configured proxy, if the port is open ---"
    PROXY=$(cat "$HOME/.proxy-url" 2>/dev/null)
    addr=${PROXY#*://}; h=${addr%%:*}; p=${addr##*:}
    if timeout 3 bash -c "exec 3<>/dev/tcp/${h}/${p}" 2>/dev/null; then
        echo "  port ${p}: OPEN"
        code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 12 -x "$PROXY" \
               "https://api.telegram.org/" 2>/dev/null)
        echo "  https://api.telegram.org via proxy -> ${code:-failed}"
    else
        echo "  port ${p}: CLOSED - the proxy setting points at nothing"
    fi
    echo

    echo "--- what gallery-dl would use ---"
    # gallery-dl reads the environment, and the bot exports these before spawning it.
    echo "  gallery_dl_env would carry:"
    env | grep -iE "proxy" | sed 's/^/    /' || echo "    (nothing)"
    echo

    echo "--- verdict ---"
    direct=0
    for target in "https://api.telegram.org/" "https://e-hentai.org/"; do
        code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 12 --noproxy '*' "$target" 2>/dev/null)
        [ -n "$code" ] && [ "$code" != "000" ] && direct=$((direct + 1))
    done
    if timeout 3 bash -c "exec 3<>/dev/tcp/${h}/${p}" 2>/dev/null; then
        echo "  proxy port is OPEN: keep BOT_PROXY set"
    elif [ "$direct" -gt 0 ]; then
        echo "  proxy port is CLOSED but direct works: TUN mode."
        echo "  FIX: remove BOT_PROXY from .env and delete ~/.proxy-url."
        echo "       A dead proxy breaks a working tunnel - every request fails on a closed port."
    else
        echo "  proxy CLOSED and direct fails: the VPN is not carrying traffic at all."
        echo "  FIX: reconnect v2rayNG."
    fi
} > "$OUT" 2>&1

echo "written to $OUT"

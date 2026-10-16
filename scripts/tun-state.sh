#!/data/data/com.termux/files/usr/bin/bash
# What is the proxy, and is its TUN mode on?
#
# Earlier evidence was contradictory: cloudflared logged "zone wlan0" on one attempt and "zone tun0"
# on another, so a TUN interface exists but is not consistently in the path. Enabling TUN mode is a
# toggle inside the proxy app, not something reachable from adb, so the useful thing here is to
# identify the app and establish exactly what the network looks like right now.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
OUT="$HOME/twitter_pixiv_tg_bot/data/tun-state.txt"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo

    echo "--- interfaces ---"
    if command -v ip >/dev/null 2>&1; then
        ip -brief addr 2>&1 | sed 's/^/  /'
    else
        ifconfig 2>&1 | grep -E '^[a-z]|inet ' | sed 's/^/  /'
    fi
    echo

    echo "--- routes ---"
    if command -v ip >/dev/null 2>&1; then
        ip route 2>&1 | head -8 | sed 's/^/  /'
    else
        netstat -rn 2>&1 | head -8 | sed 's/^/  /'
    fi
    echo

    echo "--- is a VPN active, and which app owns it? ---"
    # dumpsys is the only view of this without root-level netd access.
    dumpsys connectivity 2>/dev/null \
        | grep -iE 'VPN|TUN' | head -10 | sed 's/^/  /' || echo "  (dumpsys connectivity unreadable)"
    echo

    echo "--- packages that can be a VPN or a proxy ---"
    for pat in clash v2ray shadowsocks ssr trojan surfboard nekobox sing-box neko xray proxy vpn; do
        found=$(pm list packages 2>/dev/null | grep -i "$pat" | sed 's/package://')
        [ -n "$found" ] && printf '  %-14s %s\n' "$pat" "$(echo "$found" | tr '\n' ' ')"
    done
    echo

    echo "--- the local proxy port, and what protocol it speaks ---"
    if timeout 5 bash -c 'exec 3<>/dev/tcp/127.0.0.1/10808' 2>/dev/null; then
        echo "  127.0.0.1:10808 open (HTTP proxy)"
    else
        echo "  127.0.0.1:10808 closed"
    fi
    for p in 10809 7890 7891 7897 2080 2081; do
        timeout 3 bash -c "exec 3<>/dev/tcp/127.0.0.1/$p" 2>/dev/null && echo "  127.0.0.1:$p open"
    done
    echo

    echo "--- can the proxy actually reach the Cloudflare edge? ---"
    # Through the HTTP proxy, so this asks whether the proxy's own upstream can get there - which is
    # a different question from whether this device can.
    curl -s -o /dev/null -w '  via proxy, edge :7844 CONNECT -> %{http_code}\n' \
        --max-time 15 -x http://127.0.0.1:10808 -p \
        https://region1.v2.argotunnel.com:7844/ 2>&1 | sed 's/^/  /'
    curl -s -o /dev/null -w '  via proxy, api.cloudflare.com -> %{http_code}\n' \
        --max-time 15 -x http://127.0.0.1:10808 \
        https://api.cloudflare.com/client/v4/ips 2>&1 | sed 's/^/  /'
} > "$OUT" 2>&1

echo "written to $OUT"

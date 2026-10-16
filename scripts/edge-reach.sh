#!/data/data/com.termux/files/usr/bin/bash
# Is the Cloudflare tunnel edge reachable from this phone by any route at all?
#
# This is the decisive question. If port 7844 cannot be reached in any of these ways, no amount of
# cloudflared configuration will help, and the tunnel approach is finished on this network:
#
#   - from Termux, which goes through Android's netd and therefore through whatever the proxy does
#     with DNS and routing
#   - to the real edge IPs read over DoH (198.41.192.x)
#   - to the fake IPs the proxy hands out (198.19.x.x), which only the proxy can interpret
#   - on 7844 (the tunnel port from the SRV answer) and on 443 (in case the edge also serves there)
#
# api.cloudflare.com:443 is included as a control: it is known to work, so a failure there would
# mean the test itself is wrong rather than the network.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
OUT="$HOME/twitter_pixiv_tg_bot/data/edge-reach.txt"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo

    echo "--- network interfaces (is a VPN tunnel up?) ---"
    ip -brief addr 2>/dev/null | sed 's/^/  /' || ifconfig 2>/dev/null | grep -E '^[a-z]' | sed 's/^/  /'
    echo

    echo "--- default route ---"
    ip route 2>/dev/null | head -5 | sed 's/^/  /'
    echo

    probe() {
        local label="$1" host="$2" port="$3"
        if timeout 8 bash -c "exec 3<>/dev/tcp/$host/$port" 2>/dev/null; then
            printf '  %-46s REACHABLE\n' "$label"
            return 0
        else
            printf '  %-46s blocked or timed out\n' "$label"
            return 1
        fi
    }

    echo "--- the control: something known to work ---"
    probe "api.cloudflare.com:443 (control)" api.cloudflare.com 443
    echo

    echo "--- the real edge IPs, read over DoH ---"
    for ip in 198.41.192.107 198.41.192.227; do
        probe "$ip:7844 (tunnel port)" "$ip" 7844
        probe "$ip:443  (https)"       "$ip" 443
    done
    echo

    echo "--- the fake IPs the proxy hands out for the edge hostname ---"
    for ip in 198.19.102.70 198.19.102.86; do
        probe "$ip:7844 (tunnel port)" "$ip" 7844
    done
    echo

    echo "--- what the system resolves the edge names to right now ---"
    for h in region1.v2.argotunnel.com region2.v2.argotunnel.com; do
        printf '  %-32s ' "$h"
        python -c "
import socket,sys
try:
    print(socket.gethostbyname(sys.argv[1]))
except Exception as e:
    print('FAILED', type(e).__name__)
" "$h" 2>/dev/null || echo "?"
    done
    echo

    echo "--- and the tunnel port against the hostname, letting the proxy route it ---"
    probe "region1.v2.argotunnel.com:7844" region1.v2.argotunnel.com 7844
    probe "region2.v2.argotunnel.com:7844" region2.v2.argotunnel.com 7844
    echo

    echo "--- is anything listening locally that could be a proxy? ---"
    for port in 10808 10809 7890 7891 7897 1080 8080; do
        if timeout 3 bash -c "exec 3<>/dev/tcp/127.0.0.1/$port" 2>/dev/null; then
            echo "  127.0.0.1:$port  OPEN"
        fi
    done
} > "$OUT" 2>&1

echo "written to $OUT"

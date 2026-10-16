#!/data/data/com.termux/files/usr/bin/bash
# The transport is now right - the failure moved from DNS and connection timeouts to
#
#     TLS handshake with edge error: EOF    ip=198.19.102.86
#
# which means TCP reached something and TLS was cut off. The address is the proxy's fake IP, so the
# proxy is in the path. Two things could be wrong with that: the proxy may not carry the tunnel's
# TLS cleanly, or the fake IP may map to an edge that does not serve this tunnel.
#
# Real edge IPs were read over DoH earlier and plain TCP to them on 7844 succeeded:
#
#     198.41.192.107, 198.41.192.227, 198.41.192.27, 198.41.192.37
#
# so this tries those, with and without the proxy environment, and prints the full TLS-level detail
# for whichever fails.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"

PROJECT_DIR="$HOME/twitter_pixiv_tg_bot"
CHROOT_NAME="${CHROOT_NAME:-botapi}"
OUT="$PROJECT_DIR/data/real-edge-test.txt"

TOKEN=$(grep -m1 '^CLOUDFLARE_TUNNEL_TOKEN=' "$PROJECT_DIR/.env" | cut -d= -f2- | tr -d '\r')
PROXY=$(grep -m1 '^BOT_PROXY=' "$PROJECT_DIR/.env" | cut -d= -f2- | tr -d '"'"'"' \r')
PROXY="${PROXY:-http://127.0.0.1:10808}"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo

    attempt() {
        local label="$1" edge="$2" useproxy="$3"
        echo "--- $label ---"
        pkill -f 'cloudflared tunnel' 2>/dev/null || true
        sleep 1

        if [ "$useproxy" = "yes" ]; then
            timeout 40 proot-distro login "$CHROOT_NAME" -- \
                /usr/bin/env "TUNNEL_TOKEN=$TOKEN" "TUNNEL_EDGE=$edge" \
                    "HTTPS_PROXY=$PROXY" "HTTP_PROXY=$PROXY" \
                    /bin/sh -c \
                'exec /usr/local/bin/cloudflared tunnel --no-autoupdate --protocol http2 run --token "$TUNNEL_TOKEN"' \
                > "$PROJECT_DIR/data/real-edge.log" 2>&1
        else
            timeout 40 proot-distro login "$CHROOT_NAME" -- \
                /usr/bin/env "TUNNEL_TOKEN=$TOKEN" "TUNNEL_EDGE=$edge" /bin/sh -c \
                'exec /usr/local/bin/cloudflared tunnel --no-autoupdate --protocol http2 run --token "$TUNNEL_TOKEN"' \
                > "$PROJECT_DIR/data/real-edge.log" 2>&1
        fi

        if grep -q 'Registered tunnel connection' "$PROJECT_DIR/data/real-edge.log"; then
            echo "  SUCCESS"
            grep -E 'Registered tunnel connection|Initial protocol' \
                "$PROJECT_DIR/data/real-edge.log" | tail -2 | sed 's/^/    /'
            return 0
        fi
        grep -iE 'ERR|handshake|fail|blocked|timeout|refus' "$PROJECT_DIR/data/real-edge.log" \
            | grep -v 'Please try\|dig srv\|compressed SRV\|1.1.1.1\|github.com/golang' \
            | tail -3 | sed 's/^/    /'
        return 1
    }

    for ip in 198.41.192.107 198.41.192.227; do
        if attempt "real edge $ip:7844  direct" "$ip:7844" no; then
            echo
            echo "  >>> WORKS: TUNNEL_EDGE=$ip:7844  protocol=http2  no proxy"
            exit 0
        fi
        echo
        if attempt "real edge $ip:7844  with HTTPS_PROXY" "$ip:7844" yes; then
            echo
            echo "  >>> WORKS: TUNNEL_EDGE=$ip:7844  protocol=http2  proxy=$PROXY"
            exit 0
        fi
        echo
    done

    echo "=== none connected ==="
    echo "--- last attempt in full ---"
    tail -18 "$PROJECT_DIR/data/real-edge.log" | sed 's/^/  /'
} > "$OUT" 2>&1

echo "written to $OUT"

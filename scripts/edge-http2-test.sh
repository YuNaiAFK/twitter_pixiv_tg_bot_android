#!/data/data/com.termux/files/usr/bin/bash
# The combination that was never tried: TUNNEL_EDGE together with --protocol http2.
#
# Each half was measured alone and each failed for a different reason:
#
#   TUNNEL_EDGE alone      skipped SRV discovery, then tried QUIC - UDP, which an HTTP proxy does
#                          not carry, so it timed out
#   --protocol http2 alone skipped the UDP problem, then failed at SRV discovery, which the proxy's
#                          fake-IP DNS refuses with rcode=5
#
# Together they address both: the edge is named directly so no SRV lookup happens, and the transport
# is TCP so the proxy can carry it.
#
# And the edge is genuinely reachable over TCP - measured from Termux before this was written:
#
#   region1.v2.argotunnel.com:7844   REACHABLE
#   198.19.102.70:7844  (fake IP)    REACHABLE
#   198.41.192.107:7844 (real IP)    REACHABLE
#
# The hostname is preferred over a hardcoded address because it keeps working when Cloudflare moves
# the edge, and because resolving it yields the proxy's fake IP, which is what routes the connection
# through the proxy in the first place.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"

PROJECT_DIR="$HOME/twitter_pixiv_tg_bot"
CHROOT_NAME="${CHROOT_NAME:-botapi}"
OUT="$PROJECT_DIR/data/edge-http2-test.txt"

TOKEN=$(grep -m1 '^CLOUDFLARE_TUNNEL_TOKEN=' "$PROJECT_DIR/.env" | cut -d= -f2- | tr -d '\r')

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo "  token length: ${#TOKEN}"
    echo

    attempt() {
        local label="$1" edge="$2" protocol="$3"
        echo "--- $label ---"
        pkill -f 'cloudflared tunnel' 2>/dev/null || true
        sleep 1

        timeout 55 proot-distro login "$CHROOT_NAME" -- \
            /usr/bin/env "TUNNEL_TOKEN=$TOKEN" "TUNNEL_EDGE=$edge" /bin/sh -c \
            "exec /usr/local/bin/cloudflared tunnel --no-autoupdate --protocol $protocol run --token \"\$TUNNEL_TOKEN\"" \
            > "$PROJECT_DIR/data/edge-http2.log" 2>&1

        if grep -q 'Registered tunnel connection' "$PROJECT_DIR/data/edge-http2.log"; then
            echo "  SUCCESS"
            grep -E 'Registered tunnel connection|Initial protocol' \
                "$PROJECT_DIR/data/edge-http2.log" | tail -2 | sed 's/^/    /'
            return 0
        fi
        echo "  no connection:"
        grep -iE 'ERR|fail|blocked|timeout|refus' "$PROJECT_DIR/data/edge-http2.log" \
            | grep -v 'Please try\|dig srv\|compressed SRV\|1.1.1.1\|github.com/golang' \
            | tail -4 | sed 's/^/    /'
        return 1
    }

    if attempt "TUNNEL_EDGE=region1.v2.argotunnel.com:7844  protocol=http2" \
               "region1.v2.argotunnel.com:7844" "http2"; then
        echo
        echo "  >>> WORKS: edge=region1.v2.argotunnel.com:7844 protocol=http2"
        exit 0
    fi
    echo

    if attempt "TUNNEL_EDGE=region2.v2.argotunnel.com:7844  protocol=http2" \
               "region2.v2.argotunnel.com:7844" "http2"; then
        echo
        echo "  >>> WORKS: edge=region2.v2.argotunnel.com:7844 protocol=http2"
        exit 0
    fi
    echo

    echo "=== neither region connected ==="
    echo "--- last attempt in full ---"
    tail -20 "$PROJECT_DIR/data/edge-http2.log" | sed 's/^/  /'
} > "$OUT" 2>&1

echo "written to $OUT"

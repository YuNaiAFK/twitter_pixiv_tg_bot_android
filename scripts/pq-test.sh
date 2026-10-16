#!/data/data/com.termux/files/usr/bin/bash
# The TLS handshake to the edge on 7844 completes - a plain Python client gets TLSv1.3 through - so
# the path is not blocked. cloudflared fails on the same path with "TLS handshake with edge error:
# EOF", and it announces what makes its handshake different:
#
#     Tunnel connection curve preferences: [X25519MLKEM768 CurveID(65074) CurveP256]
#
# X25519MLKEM768 is a post-quantum hybrid key exchange. It is large, it is new, and a middlebox or
# proxy that does not expect it is exactly the kind of thing that closes a connection mid-handshake
# - which is what EOF means here. The binary reads TUNNEL_POST_QUANTUM, so this tries with it
# turned off.
#
# The protocol and edge settings from the earlier work are kept, since each was needed for a
# different reason: http2 because an HTTP proxy does not carry UDP, and TUNNEL_EDGE because the
# proxy's fake-IP DNS refuses the SRV lookup the edge discovery needs.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"

PROJECT_DIR="$HOME/twitter_pixiv_tg_bot"
CHROOT_NAME="${CHROOT_NAME:-botapi}"
OUT="$PROJECT_DIR/data/pq-test.txt"

TOKEN=$(grep -m1 '^CLOUDFLARE_TUNNEL_TOKEN=' "$PROJECT_DIR/.env" | cut -d= -f2- | tr -d '\r')

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo

    attempt() {
        local label="$1" pq="$2" protocol="$3" edge="$4"
        echo "--- $label ---"
        pkill -f 'cloudflared tunnel' 2>/dev/null || true
        sleep 1

        timeout 45 proot-distro login "$CHROOT_NAME" -- \
            /usr/bin/env "TUNNEL_TOKEN=$TOKEN" "TUNNEL_EDGE=$edge" "TUNNEL_POST_QUANTUM=$pq" \
                /bin/sh -c \
            "exec /usr/local/bin/cloudflared tunnel --no-autoupdate --protocol $protocol run --token \"\$TUNNEL_TOKEN\"" \
            > "$PROJECT_DIR/data/pq.log" 2>&1

        if grep -q 'Registered tunnel connection' "$PROJECT_DIR/data/pq.log"; then
            echo "  SUCCESS"
            grep -E 'Registered tunnel connection|Initial protocol|curve preferences' \
                "$PROJECT_DIR/data/pq.log" | tail -3 | sed 's/^/    /'
            return 0
        fi
        grep -iE 'curve preferences|ERR' "$PROJECT_DIR/data/pq.log" \
            | grep -v 'Please try\|dig srv\|compressed SRV\|1.1.1.1\|github.com/golang' \
            | tail -3 | sed 's/^/    /'
        return 1
    }

    EDGE="region1.v2.argotunnel.com:7844"

    if attempt "http2  post-quantum OFF" "false" "http2" "$EDGE"; then
        echo
        echo "  >>> WORKS: protocol=http2  TUNNEL_POST_QUANTUM=false"
        exit 0
    fi
    echo

    if attempt "http2  post-quantum ON (the default, for comparison)" "true" "http2" "$EDGE"; then
        echo
        echo "  >>> WORKS with post-quantum on; the problem was elsewhere"
        exit 0
    fi
    echo

    if attempt "quic  post-quantum OFF" "false" "quic" "$EDGE"; then
        echo
        echo "  >>> WORKS: protocol=quic  TUNNEL_POST_QUANTUM=false"
        exit 0
    fi
    echo

    echo "=== none connected ==="
    echo "--- last attempt in full ---"
    tail -20 "$PROJECT_DIR/data/pq.log" | sed 's/^/  /'
} > "$OUT" 2>&1

echo "written to $OUT"

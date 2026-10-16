#!/data/data/com.termux/files/usr/bin/bash
# Can TUNNEL_EDGE skip the SRV lookup that the phone's proxy refuses?
#
# The proxy runs in fake-IP mode: every A record comes back as 198.19.x.x and the proxy maps it to
# the real address when something connects, but SRV queries get rcode=5 and cloudflared needs one to
# find its edge.
#
# TUNNEL_EDGE sidesteps that entirely. The question is what form it takes:
#
#   a hostname  - cloudflared resolves it through the proxy's fake-IP DNS, so the connection still
#                 goes through the proxy. This is the one that matters, because the proxy is there
#                 for a reason.
#   a fake IP   - 198.19.x.x, which only means anything to the proxy.
#   a real IP   - 198.41.192.x, which would go direct and may well be blocked.
#
# Each is tried until one registers a connection. The port 7844 comes from the SRV answer, which was
# read over DoH.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"

PROJECT_DIR="$HOME/twitter_pixiv_tg_bot"
CHROOT_NAME="${CHROOT_NAME:-botapi}"
PROOT_BASE="$PREFIX/var/lib/proot-distro"
OUT="$PROJECT_DIR/data/edge-test.txt"

TOKEN=$(grep -m1 '^CLOUDFLARE_TUNNEL_TOKEN=' "$PROJECT_DIR/.env" | cut -d= -f2- | tr -d '\r')

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo "  token length: ${#TOKEN}"
    echo

    if [ -z "$TOKEN" ]; then
        echo "  *** no token in .env ***"
        exit 1
    fi

    # One entry per attempt. The last is the real IP, expected to fail but worth confirming.
    try_edge() {
        local label="$1" edge="$2"
        echo "--- TUNNEL_EDGE=$edge  ($label) ---"

        pkill -f 'cloudflared tunnel' 2>/dev/null || true
        sleep 1

        timeout 45 proot-distro login "$CHROOT_NAME" -- \
            /usr/bin/env "TUNNEL_TOKEN=$TOKEN" "TUNNEL_EDGE=$edge" /bin/sh -c \
            'exec /usr/local/bin/cloudflared tunnel --no-autoupdate run --token "$TUNNEL_TOKEN"' \
            > "$PROJECT_DIR/data/edge-attempt.log" 2>&1

        if grep -q 'Registered tunnel connection' "$PROJECT_DIR/data/edge-attempt.log"; then
            echo "  SUCCESS - a connection registered"
            grep 'Registered tunnel connection' "$PROJECT_DIR/data/edge-attempt.log" | tail -1 \
                | sed 's/^/    /'
            return 0
        fi
        echo "  no connection. Notable lines:"
        grep -iE 'error|ERR|fail|refus|timeout|SRV|edge' "$PROJECT_DIR/data/edge-attempt.log" \
            | tail -6 | sed 's/^/    /'
        return 1
    }

    if try_edge "hostname, resolved through the proxy" "region1.v2.argotunnel.com:7844"; then
        echo
        echo "  >>> USE: TUNNEL_EDGE=region1.v2.argotunnel.com:7844"
        exit 0
    fi
    echo

    if try_edge "the fake IP the proxy handed out" "198.19.102.70:7844"; then
        echo
        echo "  >>> USE: TUNNEL_EDGE=198.19.102.70:7844"
        exit 0
    fi
    echo

    if try_edge "a real Cloudflare edge IP, direct" "198.41.192.107:7844"; then
        echo
        echo "  >>> USE: TUNNEL_EDGE=198.41.192.107:7844"
        exit 0
    fi
    echo

    echo "=== none of them registered a connection ==="
    echo "--- more detail from the last attempt ---"
    tail -30 "$PROJECT_DIR/data/edge-attempt.log" | sed 's/^/  /'
} > "$OUT" 2>&1

echo "written to $OUT"

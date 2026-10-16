#!/data/data/com.termux/files/usr/bin/bash
# The edge on port 7844 is unreachable both ways, while api.cloudflare.com:443 works - because the
# proxy is in "proxy only" mode and cloudflared is not using it. cloudflared dials the edge
# directly, and a direct connection to the Cloudflare edge is blocked from this network.
#
# So the question is whether cloudflared can be made to go through the proxy:
#
#   HTTPS_PROXY / ALL_PROXY  - Go's standard variables; cloudflared's API calls honour them, and
#                              whether the tunnel connection does is what this measures.
#   --protocol http2         - TCP instead of QUIC. UDP through an HTTP proxy is not a thing, so
#                              QUIC through a proxy cannot work even in principle; TCP can.
#
# All four combinations are tried, because the answer is not predictable from the documentation and
# the cost of guessing wrong is a tunnel that looks configured and never connects.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"

PROJECT_DIR="$HOME/twitter_pixiv_tg_bot"
CHROOT_NAME="${CHROOT_NAME:-botapi}"
PROOT_BASE="$PREFIX/var/lib/proot-distro"
OUT="$PROJECT_DIR/data/proxy-test.txt"

TOKEN=$(grep -m1 '^CLOUDFLARE_TUNNEL_TOKEN=' "$PROJECT_DIR/.env" | cut -d= -f2- | tr -d '\r')
PROXY=$(grep -m1 '^BOT_PROXY=' "$PROJECT_DIR/.env" | cut -d= -f2- | tr -d '"'"'"' \r')
PROXY="${PROXY:-http://127.0.0.1:10808}"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo "  token length: ${#TOKEN}"
    echo "  proxy:        $PROXY"
    echo

    try_combo() {
        local label="$1" protocol="$2" useproxy="$3"
        echo "--- $label ---"

        pkill -f 'cloudflared tunnel' 2>/dev/null || true
        sleep 1

        if [ "$useproxy" = "yes" ]; then
            timeout 50 proot-distro login "$CHROOT_NAME" -- \
                /usr/bin/env "TUNNEL_TOKEN=$TOKEN" \
                    "HTTPS_PROXY=$PROXY" "HTTP_PROXY=$PROXY" "ALL_PROXY=$PROXY" \
                    /bin/sh -c \
                "exec /usr/local/bin/cloudflared tunnel --no-autoupdate --protocol $protocol run --token \"\$TUNNEL_TOKEN\"" \
                > "$PROJECT_DIR/data/proxy-attempt.log" 2>&1
        else
            timeout 50 proot-distro login "$CHROOT_NAME" -- \
                /usr/bin/env "TUNNEL_TOKEN=$TOKEN" /bin/sh -c \
                "exec /usr/local/bin/cloudflared tunnel --no-autoupdate --protocol $protocol run --token \"\$TUNNEL_TOKEN\"" \
                > "$PROJECT_DIR/data/proxy-attempt.log" 2>&1
        fi

        if grep -q 'Registered tunnel connection' "$PROJECT_DIR/data/proxy-attempt.log"; then
            echo "  SUCCESS"
            grep 'Registered tunnel connection' "$PROJECT_DIR/data/proxy-attempt.log" | tail -1 \
                | sed 's/^/    /'
            return 0
        fi
        echo "  no connection. Notable lines:"
        grep -iE 'ERR|error|fail|refus|blocked|timeout' "$PROJECT_DIR/data/proxy-attempt.log" \
            | grep -v 'Please try the following\|dig srv\|compressed SRV\|1.1.1.1\|github.com/golang' \
            | tail -5 | sed 's/^/    /'
        return 1
    }

    for protocol in http2 quic; do
        for useproxy in yes no; do
            if [ "$useproxy" = "yes" ]; then
                label="protocol=$protocol  through the proxy $PROXY"
            else
                label="protocol=$protocol  direct"
            fi
            if try_combo "$label" "$protocol" "$useproxy"; then
                echo
                echo "  >>> WORKS: protocol=$protocol proxy=$useproxy"
                echo "  >>> TUNNEL_PROTOCOL=$protocol  TUNNEL_USE_PROXY=$useproxy"
                exit 0
            fi
            echo
        done
    done

    echo "=== none of the four combinations connected ==="
    echo "--- full log of the last attempt ---"
    tail -25 "$PROJECT_DIR/data/proxy-attempt.log" | sed 's/^/  /'
} > "$OUT" 2>&1

echo "written to $OUT"

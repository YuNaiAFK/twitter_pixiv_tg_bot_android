#!/data/data/com.termux/files/usr/bin/bash
# Last attempt at the tunnel, with the right knob this time.
#
# TUNNEL_POST_QUANTUM=false made things worse rather than better: the curve list went from
# [X25519MLKEM768, P256] to [X25519MLKEM768] alone, so the variable does not mean "turn post-quantum
# off" - it removed the classical curve instead. The CLI exposes it properly, so this uses the flag
# and reads back which curves cloudflared actually offered, which is the only way to know.
#
# The one solid fact to build on: a plain Python TLS client completes a handshake to
# region1.v2.argotunnel.com:7844 through this same proxy, and cloudflared does not. The difference
# is in what cloudflared offers, and the post-quantum hybrid is the conspicuous part of it.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"

PROJECT_DIR="$HOME/twitter_pixiv_tg_bot"
CHROOT_NAME="${CHROOT_NAME:-botapi}"
OUT="$PROJECT_DIR/data/pq-flag-test.txt"

TOKEN=$(grep -m1 '^CLOUDFLARE_TUNNEL_TOKEN=' "$PROJECT_DIR/.env" | cut -d= -f2- | tr -d '\r')

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo

    echo "--- what does the flag look like? ---"
    proot-distro login "$CHROOT_NAME" -- /usr/local/bin/cloudflared tunnel run --help 2>&1 \
        | grep -iE 'post-quantum|quantum' | sed 's/^/  /'
    echo

    attempt() {
        local label="$1"; shift
        echo "--- $label ---"
        pkill -f 'cloudflared tunnel' 2>/dev/null || true
        sleep 1

        timeout 45 proot-distro login "$CHROOT_NAME" -- \
            /usr/bin/env "TUNNEL_TOKEN=$TOKEN" /bin/sh -c \
            "exec /usr/local/bin/cloudflared tunnel --no-autoupdate $* run --token \"\$TUNNEL_TOKEN\"" \
            > "$PROJECT_DIR/data/pqflag.log" 2>&1

        # Which curves were offered is the thing being measured, so it is always reported.
        echo "  curves: $(grep -o 'curve preferences: \[[^]]*\]' "$PROJECT_DIR/data/pqflag.log" | tail -1)"

        if grep -q 'Registered tunnel connection' "$PROJECT_DIR/data/pqflag.log"; then
            echo "  SUCCESS"
            grep -E 'Registered tunnel connection|Initial protocol' "$PROJECT_DIR/data/pqflag.log" \
                | tail -2 | sed 's/^/    /'
            return 0
        fi
        grep -E 'ERR' "$PROJECT_DIR/data/pqflag.log" \
            | grep -v 'Please try\|dig srv\|compressed SRV\|1.1.1.1\|github.com/golang' \
            | tail -2 | sed 's/^/    /'
        return 1
    }

    EDGE="--edge region1.v2.argotunnel.com:7844"

    if attempt "http2, post-quantum disabled, edge pinned" \
               "--protocol http2 --post-quantum=false $EDGE"; then
        echo; echo "  >>> WORKS: --protocol http2 --post-quantum=false --edge $EDGE"; exit 0
    fi
    echo

    if attempt "http2, defaults, edge pinned" "--protocol http2 $EDGE"; then
        echo; echo "  >>> WORKS: --protocol http2 --edge $EDGE"; exit 0
    fi
    echo

    echo "=== still nothing ==="
    echo "--- full log of the last attempt ---"
    tail -15 "$PROJECT_DIR/data/pqflag.log" | sed 's/^/  /'
} > "$OUT" 2>&1

echo "written to $OUT"

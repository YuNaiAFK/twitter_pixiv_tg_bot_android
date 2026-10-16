#!/data/data/com.termux/files/usr/bin/bash
# Put the tunnel token into .env and start the tunnel.
#
# The token came from `cloudflared tunnel token phone-alist`, which derives it from the certificate
# that `cloudflared tunnel login` wrote. Nothing was copied by hand, which is the point: three
# earlier attempts to copy the token out of the dashboard produced a 36-character UUID twice and the
# literal text <TOKEN> once.
#
# The token is a credential. It is read from a file, written to .env, and never echoed - not here,
# not to a log, not into the chat.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"

PROJECT_DIR="$HOME/twitter_pixiv_tg_bot"
ENV_FILE="$PROJECT_DIR/.env"
CHROOT_NAME="${CHROOT_NAME:-botapi}"
PROOT_BASE="$PREFIX/var/lib/proot-distro"
ROOTFS="$PROOT_BASE/containers/$CHROOT_NAME/rootfs"
TOKEN_FILE="$ROOTFS/root/.cloudflared/token.txt"
OUT="$PROJECT_DIR/data/tunnel-adopt.txt"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo

    if [ ! -s "$TOKEN_FILE" ]; then
        echo "  *** $TOKEN_FILE is missing or empty ***"
        echo "  run scripts/tunnel-commands-probe.sh first"
        exit 1
    fi

    TOKEN=$(tr -d '\r\n' < "$TOKEN_FILE")
    echo "--- token read from the certificate ---"
    echo "  length: ${#TOKEN}"
    case "$TOKEN" in
        eyJ*) echo "  prefix: eyJ (valid shape)" ;;
        *)    echo "  *** prefix is not eyJ - refusing to install it ***"; exit 1 ;;
    esac
    echo

    echo "--- writing it into .env (value not shown) ---"
    # Replace any existing line rather than appending a second one; a duplicate would leave the
    # empty one in place and the earlier value would win, because grep -m1 takes the first match -
    # which is exactly the state .env was left in by the failed attempts.
    if grep -q '^CLOUDFLARE_TUNNEL_TOKEN=' "$ENV_FILE" 2>/dev/null; then
        cp "$ENV_FILE" "$ENV_FILE.bak"
        grep -v '^CLOUDFLARE_TUNNEL_TOKEN=' "$ENV_FILE.bak" > "$ENV_FILE"
        echo "  removed the existing line (backup at .env.bak)"
    fi
    printf 'CLOUDFLARE_TUNNEL_TOKEN=%s\n' "$TOKEN" >> "$ENV_FILE"
    echo "  appended"
    echo

    echo "--- verify what .env now holds ---"
    READBACK=$(grep -m1 '^CLOUDFLARE_TUNNEL_TOKEN=' "$ENV_FILE" | cut -d= -f2-)
    echo "  lines matching: $(grep -c '^CLOUDFLARE_TUNNEL_TOKEN=' "$ENV_FILE")"
    echo "  read back length: ${#READBACK}"
    if [ "$READBACK" = "$TOKEN" ]; then
        echo "  matches what was written"
    else
        echo "  *** DOES NOT MATCH ***"
        exit 1
    fi
    echo

    echo "--- starting the tunnel ---"
    bash "$PROJECT_DIR/scripts/run-tunnel.sh" start 2>&1 | sed 's/^/  /'
    echo

    echo "--- status ---"
    bash "$PROJECT_DIR/scripts/run-tunnel.sh" status 2>&1 | sed 's/^/  /'
} > "$OUT" 2>&1

echo "written to $OUT"

#!/data/data/com.termux/files/usr/bin/bash
# Create the named tunnel, now that the certificate is in place.
#
#   bash scripts/tunnel-create.sh [name]
#
# The certificate authorises the account; this creates a tunnel inside it and writes the tunnel's
# own credentials file (a JSON with the tunnel id and secret) next to the certificate. That file,
# not a copied token, is what the tunnel runs with - which is the whole point of this route.
#
# Safe to re-run: an existing tunnel of the same name is reported rather than duplicated.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"

NAME="${1:-phone-alist}"
CHROOT_NAME="${CHROOT_NAME:-botapi}"
PROOT_BASE="$PREFIX/var/lib/proot-distro"
ROOTFS="$PROOT_BASE/containers/$CHROOT_NAME/rootfs"
OUT="$HOME/twitter_pixiv_tg_bot/data/tunnel-create.txt"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="

    if [ ! -f "$ROOTFS/root/.cloudflared/cert.pem" ]; then
        echo "  *** no cert.pem - authorise first with scripts/login-start.sh ***"
        exit 1
    fi

    echo "--- existing tunnels ---"
    proot-distro login "$CHROOT_NAME" -- /usr/local/bin/cloudflared tunnel list 2>&1 | sed 's/^/  /'
    echo

    echo "--- creating '$NAME' ---"
    proot-distro login "$CHROOT_NAME" -- /usr/local/bin/cloudflared tunnel create "$NAME" 2>&1 \
        | sed 's/^/  /'
    echo

    echo "--- tunnels now ---"
    proot-distro login "$CHROOT_NAME" -- /usr/local/bin/cloudflared tunnel list 2>&1 | sed 's/^/  /'
    echo

    echo "--- credential files ---"
    ls -la "$ROOTFS/root/.cloudflared/" 2>&1 | sed 's/^/  /'
    echo

    echo "--- the tunnel id, for the config file ---"
    for f in "$ROOTFS/root/.cloudflared/"*.json; do
        [ -f "$f" ] || continue
        echo "  $(basename "$f")"
        # Only the id and name, never the secret in the same file.
        python -c "
import json,sys
d=json.load(open(sys.argv[1]))
print('    TunnelID:', d.get('TunnelID'))
print('    AccountTag:', d.get('AccountTag'))
" "$f" 2>/dev/null || echo "    (could not read)"
    done
} > "$OUT" 2>&1

echo "written to $OUT"

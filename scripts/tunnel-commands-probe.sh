#!/data/data/com.termux/files/usr/bin/bash
# The tunnel already exists, created from the dashboard, so there is no local credentials file.
# What can be done with the certificate that is now on disk?
#
# Two candidates:
#
#   cloudflared tunnel token <name>   - prints the connector token for an existing tunnel. If this
#                                       works, the whole token-copying problem disappears: the
#                                       token is produced by cloudflared from the certificate,
#                                       never typed or pasted by anyone.
#
#   cloudflared tunnel run <name>     - traditionally needs the credentials JSON that `tunnel
#                                       create` writes. Worth testing, because if the certificate
#                                       alone is enough, no token is involved at all.
#
# The token is written to a file rather than printed, so it does not reach this log or the chat.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"

NAME="${1:-phone-alist}"
CHROOT_NAME="${CHROOT_NAME:-botapi}"
PROOT_BASE="$PREFIX/var/lib/proot-distro"
ROOTFS="$PROOT_BASE/containers/$CHROOT_NAME/rootfs"
OUT="$HOME/twitter_pixiv_tg_bot/data/tunnel-commands.txt"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo

    echo "--- the subcommands this build has ---"
    proot-distro login "$CHROOT_NAME" -- /usr/local/bin/cloudflared tunnel --help 2>&1 \
        | grep -E '^   [a-z]' | sed 's/^/  /'
    echo

    echo "--- tunnel token: does it work from the certificate? ---"
    TOKEN=$(proot-distro login "$CHROOT_NAME" -- /usr/local/bin/cloudflared tunnel token "$NAME" 2>/dev/null)
    if [ -n "$TOKEN" ]; then
        printf '%s' "$TOKEN" > "$ROOTFS/root/.cloudflared/token.txt"
        echo "  YES - a token was produced"
        echo "  length: ${#TOKEN}"
        case "$TOKEN" in
            eyJ*) echo "  prefix: eyJ (a real tunnel token)" ;;
            *)    echo "  prefix: NOT eyJ - unexpected" ;;
        esac
        echo "  saved to $ROOTFS/root/.cloudflared/token.txt (not printed here)"
    else
        echo "  no token produced; stderr:"
        proot-distro login "$CHROOT_NAME" -- /usr/local/bin/cloudflared tunnel token "$NAME" 2>&1 \
            | tail -5 | sed 's/^/    /'
    fi
    echo

    echo "--- can it run by name alone, with no credentials file? ---"
    # 12 seconds is enough to see whether it gets as far as registering connections.
    timeout 12 proot-distro login "$CHROOT_NAME" -- \
        /usr/local/bin/cloudflared tunnel --no-autoupdate run "$NAME" 2>&1 | head -14 | sed 's/^/  /'
    echo "  (exit $?  - 124 means it was still running, which is the good outcome)"
    echo

    echo "--- what is in .cloudflared now ---"
    ls -la "$ROOTFS/root/.cloudflared/" 2>&1 | sed 's/^/  /'
} > "$OUT" 2>&1

echo "written to $OUT"

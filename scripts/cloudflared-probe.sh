#!/data/data/com.termux/files/usr/bin/bash
# Can cloudflared run on this phone, and where?
#
# Cloudflare publishes cloudflared-linux-arm64. A Linux binary will not usually run in Termux -
# its interpreter is Debian's glibc loader, and Android uses /system/bin/linker64, so it fails with
# "cannot execute: required file not found", which reads like a missing file rather than the wrong
# loader. That is the same problem the Bot API server had.
#
# So this tries, in order:
#   1. the released linux-arm64 binary directly in Termux
#   2. the same binary inside the existing proot Debian container, which supplies the loader
#
# The answer decides the whole tunnel setup, so it is measured rather than assumed.
set -u
export HOME="${HOME:-/data/data/com.termux/files/home}"
export PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"

CF_DIR="$HOME/cloudflared"
DL="$CF_DIR/download"
CHROOT_NAME="${CHROOT_NAME:-botapi}"
PROOT_BASE="${PROOT_BASE:-$PREFIX/var/lib/proot-distro}"
OUT="$HOME/twitter_pixiv_tg_bot/data/cloudflared-probe.txt"

mkdir -p "$DL"
{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo "  arch: $(uname -m)"
    echo

    echo "--- what does Cloudflare publish for arm64? ---"
    REL=$(curl -s --max-time 30 https://api.github.com/repos/cloudflare/cloudflared/releases/latest)
    echo "$REL" | grep -o '"name": "[^"]*arm64[^"]*"' | sed 's/^/    /'
    TAG=$(echo "$REL" | grep -o '"tag_name": "[^"]*"' | head -1 | cut -d'"' -f4)
    echo "  latest: ${TAG:-(unknown)}"
    echo

    URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
    echo "--- downloading cloudflared-linux-arm64 ---"
    if [ ! -s "$DL/cloudflared" ]; then
        curl -fL --max-time 600 --retry 2 -o "$DL/cloudflared" "$URL" 2>&1 | tail -2
    fi
    ls -la "$DL/cloudflared" 2>/dev/null | sed 's/^/  /'
    chmod 755 "$DL/cloudflared" 2>/dev/null
    echo

    echo "--- what kind of binary is it? ---"
    file "$DL/cloudflared" 2>/dev/null | sed 's/^/  /'
    head -c 20 "$DL/cloudflared" | od -c | head -2 | sed 's/^/  /'
    echo

    echo "=== attempt 1: run it directly in Termux ==="
    "$DL/cloudflared" --version 2>&1 | head -5 | sed 's/^/  /'
    echo "  exit: $?"
    echo

    echo "=== attempt 2: inside the proot container '$CHROOT_NAME' ==="
    if [ -d "$PROOT_BASE/containers/$CHROOT_NAME/rootfs" ]; then
        ROOTFS="$PROOT_BASE/containers/$CHROOT_NAME/rootfs"
        cp "$DL/cloudflared" "$ROOTFS/usr/local/bin/cloudflared" 2>/dev/null
        chmod 755 "$ROOTFS/usr/local/bin/cloudflared" 2>/dev/null
        echo "  copied to $ROOTFS/usr/local/bin/cloudflared"
        timeout 60 proot-distro login "$CHROOT_NAME" -- /usr/local/bin/cloudflared --version \
            2>&1 | head -5 | sed 's/^/  /'
        echo "  exit: $?"
    else
        echo "  container not installed at $PROOT_BASE/containers/$CHROOT_NAME"
    fi
    echo

    echo "=== can the container see AList on 127.0.0.1:5244? ==="
    # The tunnel would run in the container and forward to AList in Termux. If the loopback is not
    # shared, the tunnel needs host networking or a different target, so this matters.
    timeout 60 proot-distro login "$CHROOT_NAME" -- /bin/sh -c \
        'command -v curl >/dev/null && curl -s -o /dev/null -w "  HTTP %{http_code}\n" --max-time 8 http://127.0.0.1:5244/api/public/settings || echo "  (no curl in the container)"' \
        2>&1 | head -5 | sed 's/^/  /'
    echo
} > "$OUT" 2>&1

echo "written to $OUT"

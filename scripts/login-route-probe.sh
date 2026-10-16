#!/data/data/com.termux/files/usr/bin/bash
# Two questions after cloudflared's login crashed with SIGSYS on faccessat2:
#
#   1. Is there a flag that skips the browser? The crash is in token.OpenBrowser, which the login
#      command calls unconditionally in this build - so a flag would avoid the syscall entirely.
#   2. Does running login inside the proot container avoid it? proot intercepts syscalls with
#      ptrace and can emulate or translate them, so faccessat2 - which Android's seccomp filter
#      rejects, raising SIGSYS - may not reach the kernel at all.
#
# The second matters even if the first works: if proot handles it, the interactive route is open
# and no token ever needs copying.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"

CF_BIN="$HOME/cloudflared/download/cloudflared"
CHROOT_NAME="${CHROOT_NAME:-botapi}"
PROOT_BASE="$PREFIX/var/lib/proot-distro"
OUT="$HOME/twitter_pixiv_tg_bot/data/login-route-probe.txt"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo

    echo "--- does tunnel login take a flag to skip the browser? ---"
    "$CF_BIN" tunnel login --help 2>&1 | sed 's/^/  /'
    echo

    echo "--- and what about run/login flags in the parent command? ---"
    "$CF_BIN" tunnel --help 2>&1 | grep -iE 'browser|login|url' | sed 's/^/  /'
    echo

    echo "=== attempt: login inside the proot container ==="
    if [ -d "$PROOT_BASE/containers/$CHROOT_NAME/rootfs" ]; then
        ROOTFS="$PROOT_BASE/containers/$CHROOT_NAME/rootfs"
        cp "$CF_BIN" "$ROOTFS/usr/local/bin/cloudflared" 2>/dev/null
        chmod 755 "$ROOTFS/usr/local/bin/cloudflared" 2>/dev/null
        echo "  binary placed in the container"
        echo
        echo "  --- running login with a 20s timeout, watching for SIGSYS ---"
        # BROWSER=echo makes cloudflared print the URL instead of handing it to a launcher where
        # it can. Even if proot fixes the syscall, launching a browser inside the container would
        # fail - the container has no Android intent bridge.
        timeout 20 proot-distro login "$CHROOT_NAME" -- /usr/bin/env BROWSER=echo \
            /usr/local/bin/cloudflared tunnel login 2>&1 | head -25 | sed 's/^/    /'
        echo "    (exit $?  - 124 means it was still running when the timeout fired, which is the"
        echo "     good outcome: it means it did not crash)"
    else
        echo "  container not installed"
    fi
} > "$OUT" 2>&1

echo "written to $OUT"

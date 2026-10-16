#!/data/data/com.termux/files/usr/bin/bash
# Start the Cloudflare login and prove it is still alive afterwards.
#
# **Why the previous attempt failed.** The login process was started with `nohup setsid` and the
# log shows it reaching "Waiting for login..." - and then it was gone. setsid detaches it from the
# controlling terminal, but Android also suspends and reclaims background work when nothing holds
# the device awake, and a Termux session that has ended takes its process group with it.
#
# So this does three things the earlier version did not:
#   - takes a wake lock, so the CPU is not allowed to suspend while waiting
#   - checks that the process is alive a few seconds after starting, rather than assuming
#   - re-checks before reporting the URL, so the operator is not sent to authorise a dead wait
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"

PROJECT_DIR="$HOME/twitter_pixiv_tg_bot"
RUN_DIR="$PROJECT_DIR/data"
LOG_FILE="$RUN_DIR/tunnel-login.log"
URL_FILE="$RUN_DIR/tunnel-login-url.txt"
PID_FILE="$RUN_DIR/tunnel-login.pid"
CHROOT_NAME="${CHROOT_NAME:-botapi}"
PROOT_BASE="$PREFIX/var/lib/proot-distro"
ROOTFS="$PROOT_BASE/containers/$CHROOT_NAME/rootfs"
OUT="$RUN_DIR/login-start.txt"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="

    if [ -f "$ROOTFS/root/.cloudflared/cert.pem" ]; then
        echo "  already logged in - certificate exists"
        exit 0
    fi

    echo "--- clearing the previous attempt ---"
    pkill -f 'cloudflared tunnel login' 2>/dev/null || true
    pkill -f "proot-distro login $CHROOT_NAME" 2>/dev/null || true
    sleep 1
    rm -f "$URL_FILE" "$PID_FILE"
    : > "$LOG_FILE"

    echo "--- taking a wake lock ---"
    if command -v termux-wake-lock >/dev/null 2>&1; then
        termux-wake-lock 2>/dev/null && echo "  wake lock held" || echo "  termux-wake-lock failed"
    else
        echo "  termux-wake-lock not available"
    fi

    echo "--- starting the login in the container ---"
    cd "$PROJECT_DIR" || exit 1
    nohup setsid proot-distro login "$CHROOT_NAME" -- \
        /usr/bin/env BROWSER=echo /usr/local/bin/cloudflared tunnel login \
        >>"$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"
    echo "  started, pid $(cat "$PID_FILE")"

    for _ in $(seq 1 25); do
        URL=$(grep -oE 'https://dash\.cloudflare\.com/[^ ]+' "$LOG_FILE" 2>/dev/null | head -1)
        [ -n "$URL" ] && break
        sleep 1
    done

    if [ -z "${URL:-}" ]; then
        echo "  *** no URL appeared; log: ***"
        tail -n 15 "$LOG_FILE" | sed 's/^/    /'
        exit 1
    fi

    printf '%s\n' "$URL" > "$URL_FILE"
    echo "  URL captured"

    # The point of this script: is it actually still running?
    sleep 5
    ALIVE=no
    if pgrep -f 'cloudflared tunnel login' >/dev/null 2>&1; then
        ALIVE=yes
    fi
    echo "  still running after 5s: $ALIVE"
    if [ "$ALIVE" = "no" ]; then
        echo "  *** it died immediately; the last lines: ***"
        tail -n 15 "$LOG_FILE" | sed 's/^/    /'
        exit 1
    fi

    echo
    echo "  authorise at:"
    echo "  $URL"
    echo

    if command -v termux-open-url >/dev/null 2>&1; then
        termux-open-url "$URL" 2>/dev/null && echo "  opened in the browser" \
            || echo "  could not open it automatically"
    fi

    echo
    echo "  It stays alive only while it is waiting, so authorise now."
} > "$OUT" 2>&1

echo "written to $OUT"

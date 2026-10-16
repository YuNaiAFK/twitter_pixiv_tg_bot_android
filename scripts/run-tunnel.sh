#!/data/data/com.termux/files/usr/bin/bash
# Run the Cloudflare Tunnel that publishes AList to the internet.
#
#   bash scripts/run-tunnel.sh start|stop|status|restart|logs
#
# **It runs inside the proot container, and that is not a preference.**
#
# cloudflared is an unmodified Go binary, so it reads /etc/resolv.conf with Go's own resolver. On
# Android that file does not exist - Termux keeps its copy at $PREFIX/etc/resolv.conf, and only
# patched programs look there. Go cannot find it, falls back to the loopback, and every lookup
# becomes:
#
#     lookup _v2-origintunneld._tcp.argotunnel.com on [::1]:53: read: connection refused
#
# curl and Python go through Android's netd instead and are unaffected, which is why the same
# device can reach api.cloudflare.com from a shell and not from cloudflared. The container has a
# real /etc/resolv.conf, so the problem does not exist there.
#
# The container also avoids the SIGSYS crash that `tunnel login` hits in Termux (faccessat2 is
# rejected by Android's seccomp filter and proot intercepts it), so both faults have the same fix.
#
# **Why a token rather than the certificate.** The tunnel already existed, created from the
# dashboard, so there is no local credentials file. `cloudflared tunnel token <name>` derives one
# from the certificate, and scripts/tunnel-adopt.sh puts it in .env - so nothing is ever copied by
# hand, which is what went wrong three times before.
#
# **Run this from the Termux app, never through `su`.** A process started with `su 10209` lands in
# the SELinux domain u:r:magisk:s0, where creating a socket is denied.
set -u
export HOME="${HOME:-/data/data/com.termux/files/home}"
export PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_DIR="$PROJECT_DIR/data"
PID_FILE="$RUN_DIR/tunnel.pid"
LOG_FILE="$RUN_DIR/tunnel.log"

CHROOT_NAME="${CHROOT_NAME:-botapi}"
PROOT_BASE="${PROOT_BASE:-$PREFIX/var/lib/proot-distro}"
ROOTFS="$PROOT_BASE/containers/$CHROOT_NAME/rootfs"

say() { printf '\033[1m%s\033[0m\n' "$1"; }
ok()  { printf '  \033[32m✓\033[0m %s\n' "$1"; }
no()  { printf '  \033[36m·\033[0m %s\n' "$1"; }
bad() { printf '  \033[31m✗\033[0m %s\n' "$1"; }

read_token() {
    # A credential: read from .env, which is not committed, and never echoed.
    if [ -f "$PROJECT_DIR/.env" ]; then
        TOKEN=$(grep -m1 '^CLOUDFLARE_TUNNEL_TOKEN=' "$PROJECT_DIR/.env" \
            | cut -d= -f2- | tr -d '"'"'"' \r')
    fi
    TOKEN="${TOKEN:-${CLOUDFLARE_TUNNEL_TOKEN:-}}"
}

running_pid() {
    if [ -f "$PID_FILE" ]; then
        pid=$(cat "$PID_FILE" 2>/dev/null || true)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            printf '%s' "$pid"
            return 0
        fi
    fi
    return 1
}

cmd_status() {
    say "Cloudflare Tunnel"
    if [ -x "$ROOTFS/usr/local/bin/cloudflared" ]; then
        ok "binary: in container '$CHROOT_NAME'"
    else
        bad "cloudflared is not in the container"
    fi
    read_token
    if [ -n "$TOKEN" ]; then
        ok "token:  set (${#TOKEN} characters)"
        case "$TOKEN" in
            eyJ*) ;;
            *) bad "token does not start with eyJ - it is not a tunnel token" ;;
        esac
    else
        bad "CLOUDFLARE_TUNNEL_TOKEN is not set in .env"
    fi
    if pid=$(running_pid); then
        ok "running (pid $pid)"
    else
        no "not running"
    fi
    if [ -f "$LOG_FILE" ]; then
        # The connector id is the useful line; it proves the tunnel registered.
        if grep -q 'Registered tunnel connection' "$LOG_FILE" 2>/dev/null; then
            ok "has registered a connection"
        fi
        if grep -q 'connIndex=' "$LOG_FILE" 2>/dev/null; then
            no "last connection line:"
            grep 'connIndex=' "$LOG_FILE" | tail -1 | sed 's/^/    /'
        fi
        no "log: $LOG_FILE ($(wc -l < "$LOG_FILE" | tr -d ' ') lines)"
    fi
}

cmd_start() {
    read_token
    if [ -z "$TOKEN" ]; then
        bad "CLOUDFLARE_TUNNEL_TOKEN is not set in .env"
        no "run scripts/tunnel-adopt.sh, which derives it from the certificate"
        exit 1
    fi
    case "$TOKEN" in
        eyJ*) ;;
        *) bad "the token in .env does not start with eyJ; run scripts/tunnel-adopt.sh"; exit 1 ;;
    esac

    if pid=$(running_pid); then
        ok "already running (pid $pid)"
        return 0
    fi

    mkdir -p "$RUN_DIR"
    say "Starting the tunnel (in container '$CHROOT_NAME')"
    : > "$LOG_FILE"

    # The token goes in through the environment rather than the command line, so it does not appear
    # in the process list where any other app on the phone could read it.
    nohup setsid proot-distro login "$CHROOT_NAME" -- \
        /usr/bin/env "TUNNEL_TOKEN=$TOKEN" /bin/sh -c \
        'exec /usr/local/bin/cloudflared tunnel --no-autoupdate run --token "$TUNNEL_TOKEN"' \
        >>"$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"

    for _ in $(seq 1 60); do
        if grep -q 'Registered tunnel connection' "$LOG_FILE" 2>/dev/null; then
            ok "connected (pid $(cat "$PID_FILE"))"
            grep 'Registered tunnel connection' "$LOG_FILE" | tail -1 | sed 's/^/    /'
            return 0
        fi
        if ! kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            bad "it exited immediately"
            tail -n 15 "$LOG_FILE" 2>/dev/null | sed 's/^/    /'
            rm -f "$PID_FILE"
            exit 1
        fi
        sleep 1
    done
    bad "no connection registered within 60s"
    tail -n 15 "$LOG_FILE" 2>/dev/null | sed 's/^/    /'
    exit 1
}

cmd_stop() {
    local pid
    if pid=$(running_pid); then
        say "Stopping pid $pid"
        kill "$pid" 2>/dev/null || true
        for _ in $(seq 1 15); do
            kill -0 "$pid" 2>/dev/null || break
            sleep 1
        done
        kill -9 "$pid" 2>/dev/null || true
        ok "stopped"
    else
        no "not running"
    fi
    if pgrep -f 'cloudflared tunnel' >/dev/null 2>&1; then
        no "a cloudflared process survived; stopping it too"
        pkill -f 'cloudflared tunnel' 2>/dev/null || true
        sleep 1
        pkill -9 -f 'cloudflared tunnel' 2>/dev/null || true
    fi
    pkill -f "proot-distro login $CHROOT_NAME" 2>/dev/null || true
    rm -f "$PID_FILE"
}

mkdir -p "$RUN_DIR"

case "${1:-status}" in
    start)   cmd_start ;;
    stop)    cmd_stop ;;
    restart) cmd_stop; cmd_start ;;
    status)  cmd_status ;;
    logs)    tail -n "${2:-60}" "$LOG_FILE" ;;
    *) echo "usage: $0 start|stop|restart|status|logs [lines]" >&2; exit 2 ;;
esac

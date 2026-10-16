#!/data/data/com.termux/files/usr/bin/bash
# Run the Cloudflare Tunnel that publishes AList to the internet.
#
#   bash scripts/run-tunnel.sh start|stop|status|restart|logs|url
#
# **Why this exists.** Telegraph fetches the images in a page itself, so the URLs have to be
# reachable from the public internet. AList runs on the phone, which is behind NAT, so without a
# tunnel nothing outside the device can load a single image. With one, the gallery gets a stable
# public address and - unlike e-hentai's signed links - that address does not expire, which is what
# removes the need to regenerate pages at all.
#
# **cloudflared runs natively here.** It is a statically linked Go binary, so the Termux build runs
# directly rather than needing the proot container the Bot API server requires. Measured:
#
#     cloudflared version 2026.10.1 (built 2026-10-15-17:08 UTC)
#
# **Run this from the Termux app, never through `su`.** A process started with `su 10209` lands in
# the SELinux domain u:r:magisk:s0, where creating a socket is denied.
set -u
export HOME="${HOME:-/data/data/com.termux/files/home}"
export PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CF_BIN="${CF_BIN:-$HOME/cloudflared/download/cloudflared}"
RUN_DIR="$PROJECT_DIR/data"
PID_FILE="$RUN_DIR/tunnel.pid"
LOG_FILE="$RUN_DIR/tunnel.log"

say() { printf '\033[1m%s\033[0m\n' "$1"; }
ok()  { printf '  \033[32m✓\033[0m %s\n' "$1"; }
no()  { printf '  \033[36m·\033[0m %s\n' "$1"; }
bad() { printf '  \033[31m✗\033[0m %s\n' "$1"; }

read_token() {
    # The token is a credential: it is read from .env, which is not committed, and is never echoed.
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
    if [ -x "$CF_BIN" ]; then
        ok "binary: $("$CF_BIN" --version 2>/dev/null | head -1)"
    else
        bad "cloudflared missing at $CF_BIN - run scripts/cloudflared-probe.sh"
    fi
    read_token
    if [ -n "$TOKEN" ]; then
        # Length only. The token is a credential and must not reach a log or a screenshot.
        ok "token:  set (${#TOKEN} characters)"
    else
        bad "CLOUDFLARE_TUNNEL_TOKEN is not set in .env"
    fi
    if pid=$(running_pid); then
        ok "running (pid $pid)"
    else
        no "not running"
    fi
    if [ -f "$LOG_FILE" ]; then
        # The public hostname is in the log; showing it saves a trip to the dashboard.
        host=$(grep -oE 'https?://[a-zA-Z0-9.-]+' "$LOG_FILE" 2>/dev/null | tail -1)
        [ -n "$host" ] && no "seen: $host"
        no "log: $LOG_FILE ($(wc -l < "$LOG_FILE" | tr -d ' ') lines)"
    fi
}

cmd_start() {
    read_token
    if [ -z "$TOKEN" ]; then
        bad "CLOUDFLARE_TUNNEL_TOKEN is not set in .env"
        printf '  Create a tunnel at dash.cloudflare.com -> Zero Trust -> Networks -> Tunnels,\n'
        printf '  add a public hostname pointing at http://127.0.0.1:5244, then put the token in .env\n'
        exit 1
    fi
    [ -x "$CF_BIN" ] || { bad "cloudflared missing at $CF_BIN"; exit 1; }

    if pid=$(running_pid); then
        ok "already running (pid $pid)"
        return 0
    fi

    mkdir -p "$RUN_DIR"
    say "Starting the tunnel"
    # --no-autoupdate: a binary that replaces itself under a service manager is how a working
    # tunnel becomes a stopped one after a reboot it did not survive.
    nohup setsid "$CF_BIN" tunnel --no-autoupdate run --token "$TOKEN" \
        >>"$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"

    for _ in $(seq 1 40); do
        if grep -q 'Registered tunnel connection' "$LOG_FILE" 2>/dev/null; then
            ok "connected (pid $(cat "$PID_FILE"))"
            return 0
        fi
        if ! kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            bad "it exited immediately"
            tail -n 20 "$LOG_FILE" 2>/dev/null | sed 's/^/    /'
            rm -f "$PID_FILE"
            exit 1
        fi
        sleep 1
    done
    bad "no connection registered within 40s"
    tail -n 20 "$LOG_FILE" 2>/dev/null | sed 's/^/    /'
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

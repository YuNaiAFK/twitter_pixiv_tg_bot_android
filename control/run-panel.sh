#!/data/data/com.termux/files/usr/bin/bash
# Start, stop and inspect the control panel.
#
#   bash control/run-panel.sh start|stop|status|restart|logs|url
#
# The panel is a convenience over the command line, not a replacement: it shells out to
# run-bot.sh and run-server.sh, so the two can never disagree about what "start" means.
#
# **It is deliberately not part of the boot script.** The bot and the server need to come back
# after a reboot; the panel is only wanted when someone is there to look at it, and leaving an
# HTTP service bound - even on loopback - for no reason is a habit worth not forming.

set -u
export PATH="${PREFIX:-/data/data/com.termux/files/usr}/bin:${PREFIX:-/data/data/com.termux/files/usr}/bin/applets:$PATH"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PANEL_PY="$PROJECT_DIR/control/panel.py"
RUN_DIR="$PROJECT_DIR/data"
PID_FILE="$RUN_DIR/panel.pid"
LOG_FILE="$RUN_DIR/panel.log"
HOST="${PANEL_HOST:-127.0.0.1}"
PORT="${PANEL_PORT:-8090}"

say() { printf '\033[1m%s\033[0m\n' "$1"; }
ok()  { printf '  \033[32m✓\033[0m %s\n' "$1"; }
no()  { printf '  \033[36m·\033[0m %s\n' "$1"; }
bad() { printf '  \033[31m✗\033[0m %s\n' "$1"; }

running_pid() {
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null || true)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            printf '%s' "$pid"
            return 0
        fi
    fi
    # Fall back to the process list: a stale pid file must not make the panel unstoppable.
    local found
    found=$(pgrep -f "python.*$PANEL_PY" 2>/dev/null | head -1 || true)
    [ -n "$found" ] && { printf '%s' "$found"; return 0; }
    return 1
}

port_answers() {
    # bash's /dev/tcp; mksh has none, which is why this script insists on bash.
    (exec 3<>"/dev/tcp/$HOST/$PORT") 2>/dev/null && { exec 3<&- 3>&- 2>/dev/null; return 0; }
    return 1
}

cmd_start() {
    if pid=$(running_pid); then
        ok "already running (pid $pid)"
        return 0
    fi
    if port_answers; then
        bad "port $PORT is already in use by something else"
        exit 1
    fi
    [ -f "$PANEL_PY" ] || { bad "missing $PANEL_PY"; exit 1; }

    mkdir -p "$RUN_DIR"
    say "Starting the control panel"
    nohup setsid python "$PANEL_PY" --host "$HOST" --port "$PORT" >>"$LOG_FILE" 2>&1 &
    started=$!
    sleep 2
    if kill -0 "$started" 2>/dev/null; then
        # Written only once the process is known to be alive; a failed start that recorded its
        # dead pid is what made `--stop` useless on the bot script.
        echo "$started" > "$PID_FILE"
        ok "started (pid $started)"
        no "log: $LOG_FILE"
        printf '\n    Open:  http://%s:%s/\n' "$HOST" "$PORT"
        printf '    In Chrome use the menu and "Add to Home screen" for an app-like icon.\n'
    else
        rm -f "$PID_FILE"
        bad "it exited immediately - last lines of the log:"
        tail -n 15 "$LOG_FILE" 2>/dev/null | sed 's/^/      /' || true
        exit 1
    fi
}

cmd_stop() {
    stopped=0
    if pid=$(running_pid); then
        say "Stopping pid $pid"
        kill "$pid" 2>/dev/null || true
        sleep 1
        kill -9 "$pid" 2>/dev/null || true
        stopped=1
    fi
    # Anything else still serving the panel, in case the pid file lied.
    if pgrep -f "python.*$PANEL_PY" >/dev/null 2>&1; then
        pkill -f "python.*$PANEL_PY" 2>/dev/null || true
        sleep 1
        pkill -9 -f "python.*$PANEL_PY" 2>/dev/null || true
        stopped=1
    fi
    rm -f "$PID_FILE"
    [ "$stopped" = "1" ] && ok "stopped" || no "not running"
}

cmd_status() {
    say "Control panel"
    if pid=$(running_pid); then ok "running (pid $pid)"; else no "not running"; fi
    if port_answers; then
        ok "http://$HOST:$PORT/ answers"
    else
        no "nothing listening on $HOST:$PORT"
    fi
    no "log: $LOG_FILE"
    # The settings it can change are worth restating where they are visible.
    printf '\n    bot:    %s\n' "$([ -f "$RUN_DIR/bot.pid" ] && kill -0 "$(cat "$RUN_DIR/bot.pid" 2>/dev/null)" 2>/dev/null && echo running || echo 'not running (pid file)')"
    printf '    server: %s\n' "$(grep -q '1F91' /proc/net/tcp 2>/dev/null && echo 'listening on 8081' || echo 'not listening on 8081')"
}

case "${1:-status}" in
    start)   cmd_start ;;
    stop)    cmd_stop ;;
    restart) cmd_stop; cmd_start ;;
    status)  cmd_status ;;
    url)     printf 'http://%s:%s/\n' "$HOST" "$PORT" ;;
    logs)    tail -n "${2:-60}" "$LOG_FILE" ;;
    *) echo "usage: $0 start|stop|restart|status|url|logs [lines]" >&2; exit 2 ;;
esac

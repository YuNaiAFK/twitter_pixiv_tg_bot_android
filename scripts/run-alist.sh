#!/data/data/com.termux/files/usr/bin/bash
# Start, stop and inspect the local AList instance that will serve the gallery images.
#
#   bash scripts/run-alist.sh start|stop|status|restart|logs|password
#
# AList is the image host for this project: the bot writes the display images it downloads from
# e-hentai into $ALIST_DIR/galleries, and AList serves that directory over HTTP. A tunnel in front
# of it makes those URLs reachable by Telegram, which is what lets a Telegraph page embed images
# that never expire - the problem the whole 重新生成 feature existed to work around.
#
# **Run this from the Termux app, never through `su`.** A process started with `su 10209` lands in
# the SELinux domain u:r:magisk:s0, where creating a socket is denied - AList would report a bind
# failure, or start and be unreachable, and the cause would look like a port problem.
#
# **Why the Android build rather than the Debian one.** AList publishes alist-android-arm64, so it
# runs here directly instead of inside the proot container. The images it serves are on the phone,
# and each layer between the two is a place for the path to be wrong.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export HOME="${HOME:-/data/data/com.termux/files/home}"
export PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"

ALIST_DIR="${ALIST_DIR:-$HOME/alist}"
ALIST_BIN="$ALIST_DIR/alist"
ALIST_DATA="$ALIST_DIR/data"
GALLERY_DIR="${GALLERY_DIR:-$ALIST_DIR/galleries}"
ALIST_PORT="${ALIST_PORT:-5244}"
RUN_DIR="$PROJECT_DIR/data"
PID_FILE="$RUN_DIR/alist.pid"
LOG_FILE="$RUN_DIR/alist.log"

say() { printf '\033[1m%s\033[0m\n' "$1"; }
ok()  { printf '  \033[32m✓\033[0m %s\n' "$1"; }
no()  { printf '  \033[36m·\033[0m %s\n' "$1"; }
bad() { printf '  \033[31m✗\033[0m %s\n' "$1"; }

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

port_answers() {
    (exec 3<>"/dev/tcp/127.0.0.1/$ALIST_PORT") >/dev/null 2>&1 && { exec 3<&- 3>&-; return 0; }
    return 1
}

cmd_status() {
    say "AList"
    if [ -x "$ALIST_BIN" ]; then
        ok "binary: $ALIST_BIN"
    else
        bad "binary missing - run scripts/install-alist.sh"
    fi
    if [ -d "$ALIST_DATA" ]; then
        ok "data:   $ALIST_DATA"
    else
        bad "data directory missing - run scripts/install-alist.sh"
    fi
    count=$(find "$GALLERY_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
    size=$(du -sh "$GALLERY_DIR" 2>/dev/null | cut -f1 || echo "?")
    ok "images: $GALLERY_DIR ($count galleries, $size)"

    if pid=$(running_pid); then
        ok "running (pid $pid)"
    else
        no "not running (no live pid file)"
    fi
    if port_answers; then
        ok "port $ALIST_PORT answers"
    else
        no "port $ALIST_PORT does not answer"
    fi
    if [ -f "$LOG_FILE" ]; then
        no "log: $LOG_FILE ($(wc -l < "$LOG_FILE" | tr -d ' ') lines)"
    fi
    no "panel: http://127.0.0.1:$ALIST_PORT"
}

cmd_start() {
    [ -x "$ALIST_BIN" ] || { bad "binary missing - run scripts/install-alist.sh"; exit 1; }
    if pid=$(running_pid); then
        ok "already running (pid $pid)"
        return 0
    fi
    if port_answers; then
        bad "port $ALIST_PORT is already in use by something else"
        exit 1
    fi

    mkdir -p "$RUN_DIR" "$GALLERY_DIR" "$ALIST_DATA"

    say "Starting AList on :$ALIST_PORT"
    # setsid so it survives the Termux session ending, matching how the other services here run.
    # --data keeps the database and config inside the project-adjacent directory rather than
    # wherever the working directory happens to be.
    cd "$ALIST_DIR"
    nohup setsid "$ALIST_BIN" server --data "$ALIST_DATA" >>"$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"

    for _ in $(seq 1 30); do
        if port_answers; then
            ok "started (pid $(cat "$PID_FILE"))"
            return 0
        fi
        sleep 1
    done
    bad "it did not start listening within 30s"
    printf '  last lines of %s:\n' "$LOG_FILE"
    tail -n 20 "$LOG_FILE" 2>/dev/null | sed 's/^/    /' || true
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
    # A survivor would keep the port bound and make the next start fail with a message about the
    # port rather than about this script's own previous run.
    if pgrep -f "alist server --data $ALIST_DATA" >/dev/null 2>&1; then
        no "an AList process survived; stopping it too"
        pkill -f "alist server --data $ALIST_DATA" 2>/dev/null || true
        sleep 1
        pkill -9 -f "alist server --data $ALIST_DATA" 2>/dev/null || true
    fi
    rm -f "$PID_FILE"
}

cmd_password() {
    # Sets the admin password rather than printing the generated one. The generated password is
    # written once to the first-run log and is easy to lose; a value the operator chooses is not.
    if [ "$#" -lt 1 ] || [ -z "${1:-}" ]; then
        bad "usage: $0 password <new-password>"
        exit 2
    fi
    say "Setting the AList admin password"
    "$ALIST_BIN" admin set "$1" --data "$ALIST_DATA"
    ok "done - log in as 'admin'"
}

mkdir -p "$RUN_DIR"

case "${1:-status}" in
    start)    cmd_start ;;
    stop)     cmd_stop ;;
    restart)  cmd_stop; cmd_start ;;
    status)   cmd_status ;;
    logs)     tail -n "${2:-60}" "$LOG_FILE" ;;
    password) shift; cmd_password "$@" ;;
    *) echo "usage: $0 start|stop|restart|status|logs|password <pw>" >&2; exit 2 ;;
esac

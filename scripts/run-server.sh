#!/data/data/com.termux/files/usr/bin/bash
# Start, stop and inspect the self-hosted Bot API server.
#
#   bash scripts/run-server.sh start|stop|status|restart|logs
#
# The server is what raises the upload limit from 50 MB to 2000 MB, so its state is worth
# being able to ask about directly rather than inferring it from the bot's behaviour.
#
# It runs with nohup + setsid so it survives the Termux session ending. `start_new_session`
# in the Python platform layer does the same job for the bot's own child processes; a shell
# has no equivalent flag, so setsid is it.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIX_TERMUX="${PREFIX:-/data/data/com.termux/files/usr}"
CHROOT_NAME="${CHROOT_NAME:-botapi}"
PROOT_BASE="${PROOT_BASE:-$PREFIX_TERMUX/var/lib/proot-distro}"
API_PORT="${API_PORT:-8081}"
RUN_DIR="$PROJECT_DIR/data"
PID_FILE="$RUN_DIR/bot-api.pid"
LOG_FILE="$RUN_DIR/bot-api.log"

# **The rootfs moved in proot-distro 5.x, and the binary must be run through proot.**
#
# Two separate problems, both of which made this script useless as written:
#
#   1. The path. 5.x keeps the rootfs at containers/<name>/rootfs; 4.x used
#      installed-rootfs/<name>. Only the old path was checked, so the script reported
#      "binary missing" for a binary that was there.
#
#   2. The binary cannot be executed directly. Its interpreter is
#      /lib/ld-linux-aarch64.so.1 - Debian's glibc loader. Android has /system/bin/linker64
#      instead, so running it gives "cannot execute: required file not found", which reads like
#      a missing file rather than the wrong loader. It has to go through `proot-distro login`,
#      which supplies the chroot's loader and libraries.
#
# The loopback is shared: measured from the Termux app, a listener started inside the chroot on
# 0.0.0.0:8099 accepted a connection from Termux, so the bot can reach this server at
# 127.0.0.1:$API_PORT even though it lives outside the chroot.
#
# **Run this script from the Termux app, never through `su`.** A process started with
# `su 10209` lands in the SELinux domain u:r:magisk:s0, where creating a socket fails with
# PermissionError / "socket: Permission denied" - the network looks broken when it is not.
if [ -d "$PROOT_BASE/containers/$CHROOT_NAME/rootfs" ]; then
    CHROOT_ROOT="$PROOT_BASE/containers/$CHROOT_NAME/rootfs"
else
    CHROOT_ROOT="${CHROOT_ROOT:-$PROOT_BASE/installed-rootfs/$CHROOT_NAME}"
fi
BINARY="$CHROOT_ROOT/usr/local/bin/telegram-bot-api"

# The server's working directory, as seen from inside the chroot. `--dir` is validated with
# realpath and the server refuses to start if it does not already exist, so it is created from
# Termux and referenced by its chroot path.
SERVER_DIR_CHROOT="/root/telegram-bot-api"
SERVER_DIR_HOST="$CHROOT_ROOT/root/telegram-bot-api"

say() { printf '\033[1m%s\033[0m\n' "$1"; }
ok()  { printf '  \033[32m✓\033[0m %s\n' "$1"; }
no()  { printf '  \033[36m·\033[0m %s\n' "$1"; }
bad() { printf '  \033[31m✗\033[0m %s\n' "$1"; }

load_env() {
    # Read the two values the server itself needs. Not `source`: .env is not shell syntax and
    # a value containing spaces would be word-split.
    if [ -f "$PROJECT_DIR/.env" ]; then
        API_ID=$(grep -m1 '^TELEGRAM_API_ID='   "$PROJECT_DIR/.env" | cut -d= -f2- | tr -d '"'"'"' \r')
        API_HASH=$(grep -m1 '^TELEGRAM_API_HASH=' "$PROJECT_DIR/.env" | cut -d= -f2- | tr -d '"'"'"' \r')
    fi
    API_ID="${API_ID:-${TELEGRAM_API_ID:-}}"
    API_HASH="${API_HASH:-${TELEGRAM_API_HASH:-}}"
}

running_pid() {
    # The pid file is the fast path; the port is the truth. A server started by hand, or one
    # whose pid file was lost, is still found by the port check.
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
    # No curl dependency: a TCP connect is enough, and the server needs a token for anything
    # more, which this script deliberately does not read.
    (exec 3<>"/dev/tcp/127.0.0.1/$API_PORT") >/dev/null 2>&1 && { exec 3<&- 3>&-; return 0; }
    return 1
}

cmd_status() {
    say "Bot API server"
    if ! [ -d "$CHROOT_ROOT" ]; then
        no "chroot '$CHROOT_NAME' not installed"
    elif [ -x "$BINARY" ]; then
        ok "binary: $BINARY"
    else
        bad "binary missing at $BINARY - run setup-termux.sh"
    fi
    if pid=$(running_pid); then
        ok "running (pid $pid)"
    else
        no "not running (no live pid file)"
    fi
    if port_answers; then
        ok "port $API_PORT answers"
    else
        no "port $API_PORT does not answer"
    fi
    if [ -f "$LOG_FILE" ]; then
        no "log: $LOG_FILE ($(wc -l < "$LOG_FILE" | tr -d ' ') lines)"
    fi
}

cmd_start() {
    load_env
    [ -n "$API_ID" ]   || { bad "TELEGRAM_API_ID is not set in .env"; exit 1; }
    [ -n "$API_HASH" ] || { bad "TELEGRAM_API_HASH is not set in .env"; exit 1; }

    if pid=$(running_pid); then
        ok "already running (pid $pid)"
        return 0
    fi
    if port_answers; then
        bad "port $API_PORT is already in use by something else"
        exit 1
    fi
    [ -x "$BINARY" ] || { bad "binary missing at $BINARY - run setup-termux.sh"; exit 1; }

    # The server validates --dir with realpath and will not create it, so it has to exist first.
    # Creating it from Termux is what makes it owned by the Termux user, which is the same user
    # the chroot runs as.
    mkdir -p "$RUN_DIR" "$SERVER_DIR_HOST"

    say "Starting the Bot API server on :$API_PORT"
    # --local is what allows an upload by file path, which is the whole reason for running
    # this at all: the bot hands Telegram a path on disk instead of re-uploading bytes.
    # --dir is where Telegram stores the downloaded files, so it must be writable and large.
    #
    # `proot-distro login` is required, not optional: see the note at the top about the loader.
    # The pid recorded is proot's, which is the process that stays alive; stopping it takes the
    # server down with it, which is what cmd_stop relies on.
    nohup setsid proot-distro login "$CHROOT_NAME" -- \
        /usr/local/bin/telegram-bot-api \
        --api-id="$API_ID" \
        --api-hash="$API_HASH" \
        --local \
        --http-port="$API_PORT" \
        --dir="$SERVER_DIR_CHROOT" \
        >>"$LOG_FILE" 2>&1 &
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

    # **The pid is proot's, and killing proot can leave the server behind.**
    #
    # proot runs telegram-bot-api as a child; whether the child dies with the parent depends on
    # timing, and a survivor keeps the port bound, so the next start fails with "port 8081 is
    # already in use by something else" - a misleading message, because the something is this
    # script's own previous run. So anything still holding the server is cleaned up explicitly.
    if pgrep -f 'telegram-bot-api.*--http-port=' >/dev/null 2>&1; then
        no "a server process survived; stopping it too"
        pkill -f 'telegram-bot-api.*--http-port=' 2>/dev/null || true
        sleep 1
        pkill -9 -f 'telegram-bot-api.*--http-port=' 2>/dev/null || true
    fi
    # A proot wrapper with no server left underneath would also keep the pid file stale.
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

#!/data/data/com.termux/files/usr/bin/bash
# Start the bot, keeping it awake, and report whether the full upload limit is in force.
#
#   bash scripts/run-bot.sh              # foreground (Ctrl-C to stop)
#   bash scripts/run-bot.sh --background # survives the session ending
#   bash scripts/run-bot.sh --status
#
# Two Android-specific things this handles that the Windows run.bat has no equivalent for:
#
#   termux-wake-lock   without it the CPU sleeps and polls stop arriving, so the bot looks
#                      dead while the process is still alive. This is the single most common
#                      reason a phone-hosted bot "stops working".
#   the server check   the Windows version starts Docker; here it starts the chroot server,
#                      and it reports the resulting upload limit so a fallback to the public
#                      API is visible rather than silent.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_DIR="$PROJECT_DIR/data"
PID_FILE="$RUN_DIR/bot.pid"
LOG_FILE="$RUN_DIR/bot.log"
API_PORT="${API_PORT:-8081}"
MODE="foreground"

case "${1:-}" in
    --background) MODE="background" ;;
    --status)     MODE="status" ;;
    --stop)       MODE="stop" ;;
    -h|--help)    sed -n '2,12p' "$0"; exit 0 ;;
    "")           ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
esac

say() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
ok()  { printf '    \033[32m✓\033[0m %s\n' "$1"; }
no()  { printf '    \033[36m·\033[0m %s\n' "$1"; }
bad() { printf '    \033[31m✗\033[0m %s\n' "$1"; }
warn(){ printf '    \033[33m!\033[0m %s\n' "$1"; }

export BOT_BASE_DIR="${BOT_BASE_DIR:-$PROJECT_DIR}"
mkdir -p "$RUN_DIR"

if [ "$MODE" = "status" ]; then
    say "Bot status"
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        ok "running (pid $(cat "$PID_FILE"))"
    else
        no "not running"
    fi
    if [ -f "$LOG_FILE" ]; then
        no "log: $LOG_FILE"
        printf '    last 5 lines:\n'
        tail -n 5 "$LOG_FILE" | sed 's/^/      /' || true
    fi
    exit 0
fi

# -------------------- wake lock --------------------

if command -v termux-wake-lock >/dev/null 2>&1; then
    say "Wake lock"
    termux-wake-lock && ok "acquired (the CPU will not sleep under the bot)"
    # Released by run-bot.sh --stop or by the process exiting; see the trap below.
else
    say "Wake lock"
    warn "termux-wake-lock not found - install termux-api, or the bot may stop polling"
    warn "when the screen has been off for a while"
fi

# -------------------- the server (this is the 2000 MB) --------------------

say "Self-hosted Bot API server"
if (exec 3<>"/dev/tcp/127.0.0.1/$API_PORT") >/dev/null 2>&1; then
    exec 3<&- 3>&- 2>/dev/null || true
    ok "responding on :$API_PORT"
else
    no "not responding on :$API_PORT"
    printf '    starting it...\n'
    if bash "$PROJECT_DIR/scripts/run-server.sh" start 2>&1 | sed 's/^/      /'; then
        ok "started"
    else
        warn "could not start it - the bot will use the public API (50 MB)"
        warn "run 'bash scripts/run-server.sh status' to see why"
    fi
fi

# -------------------- .env sanity --------------------

say "Configuration"
if [ ! -f "$PROJECT_DIR/.env" ]; then
    bad "no .env - copy .env.example and fill in BOT_TOKEN"
    exit 1
fi
if grep -q '^BOT_TOKEN=.\+' "$PROJECT_DIR/.env"; then
    ok "BOT_TOKEN is set"
else
    bad "BOT_TOKEN is empty in .env"
    exit 1
fi
if grep -q '^TELEGRAM_LOCAL=1' "$PROJECT_DIR/.env"; then
    ok "TELEGRAM_LOCAL=1 (uploads by path)"
else
    warn "TELEGRAM_LOCAL is not 1 - the limit will stay at 50 MB even with the server up"
fi

# -------------------- run --------------------

start_bot() {
    exec python "$PROJECT_DIR/bot/bot.py"
}

case "$MODE" in
    foreground)
        say "Starting the bot (Ctrl-C to stop)"
        # Release the wake lock however this exits, so a crash does not leave it held and
        # drain the battery.
        cleanup() {
            printf '\n'
            command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-unlock 2>/dev/null || true
            ok "wake lock released"
        }
        trap cleanup EXIT INT TERM
        start_bot
        ;;
    background)
        say "Starting the bot in the background"
        nohup setsid python "$PROJECT_DIR/bot/bot.py" >>"$LOG_FILE" 2>&1 &
        started_pid=$!
        sleep 5
        if kill -0 "$started_pid" 2>/dev/null; then
            # **The pid file is written only after the process is known to be alive.**
            #
            # It used to be written immediately, before the liveness check. A start that failed
            # - because another instance held the single-instance lock, for instance - therefore
            # left its dead pid in the file, and `--stop` then read that pid, found nothing
            # running, and left the *real* bot running and holding the Telegram poll. Recovering
            # from that needed the process to be killed by hand.
            echo "$started_pid" > "$PID_FILE"
            ok "started (pid $started_pid)"
            no "log: $LOG_FILE"
            printf '\n    Stop it with:  bash scripts/run-bot.sh --stop\n'
            printf '    The wake lock is held for as long as it runs; release it with\n'
            printf '    termux-wake-unlock if you stop the bot some other way.\n'
        else
            # Nothing to record: this attempt is gone. Leaving a pid behind is what caused the
            # problem above.
            rm -f "$PID_FILE"
            bad "it exited immediately - last lines of the log:"
            tail -n 15 "$LOG_FILE" | sed 's/^/      /' || true
            # A common cause is worth naming, because the log line for it is buried in the
            # startup banner of the *other* instance rather than shown as an error here.
            if tail -n 25 "$LOG_FILE" 2>/dev/null | grep -q '已經有另一個機器人正在執行'; then
                printf '\n    %sanother bot is already running and holds the single-instance lock%s\n' \
                    "$(printf '\033[33m')" "$(printf '\033[0m')"
                printf '    stop it first:  bash scripts/run-bot.sh --stop\n'
            fi
            exit 1
        fi
        ;;
    stop)
        # **The pid file is a hint, not the truth.** A stale one - left by an older version of
        # this script, or by a bot that died without cleaning up - names a process that is not
        # there, and trusting it means the real bot keeps running and keeps holding the Telegram
        # poll, so the next start is refused by the single-instance lock and the recovery is a
        # manual `kill`. So the file is tried first and the process list is the fallback.
        stopped_any=0
        if [ -f "$PID_FILE" ]; then
            pid=$(cat "$PID_FILE" 2>/dev/null || true)
            if [ -n "$pid" ]; then
                if kill -0 "$pid" 2>/dev/null; then
                    kill "$pid" 2>/dev/null || true
                    sleep 2
                    kill -9 "$pid" 2>/dev/null || true
                    ok "stopped pid $pid"
                    stopped_any=1
                else
                    no "pid $pid from the pid file is not running"
                fi
            fi
            rm -f "$PID_FILE"
        else
            no "no pid file"
        fi

        # Anything still running bot.py, whether or not a pid file named it. The pattern is
        # specific to this project's entry point so an unrelated python process is not hit.
        if pgrep -f "$PROJECT_DIR/bot/bot.py" >/dev/null 2>&1; then
            no "found bot.py still running; stopping it"
            pkill -f "$PROJECT_DIR/bot/bot.py" 2>/dev/null || true
            sleep 2
            pkill -9 -f "$PROJECT_DIR/bot/bot.py" 2>/dev/null || true
            stopped_any=1
        fi

        if [ "$stopped_any" = "1" ]; then
            command -v termux-wake-unlock >/dev/null 2>&1 && termux-wake-unlock 2>/dev/null || true
            ok "wake lock released"
        else
            no "nothing was running"
        fi
        ;;
esac

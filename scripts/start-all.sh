#!/data/data/com.termux/files/usr/bin/bash
# Start everything this project needs, in dependency order: server, then bot, then panel.
#
#   bash scripts/start-all.sh            # start whatever is not already up
#   bash scripts/start-all.sh --status   # report only, change nothing
#   bash scripts/start-all.sh --restart  # stop and start everything
#
# **This exists so that nothing needs to be typed by hand.** Before it, the panel had to be
# started from a terminal, and the panel is what the phone app talks to - so the app could not be
# used until someone had opened Termux and run a command. The app now sends
# `com.termux.RUN_COMMAND` with this script (see enable-external-apps.sh), which closes that loop.
#
# Order matters and each step is waited for:
#
#   server  the bot is configured with TELEGRAM_LOCAL=1, so it expects http://127.0.0.1:8081
#   bot     after the server, or it fails its startup probe and falls back to the 50 MB API
#   panel   last, because it is what the app polls; starting it first would let the app see a
#           panel whose buttons then fail
#
# Every step is idempotent: run-server.sh and run-bot.sh already detect a live instance, and the
# panel does the same, so a second run reports "already running" rather than starting duplicates.

set -u
export PATH="${PREFIX:-/data/data/com.termux/files/usr}/bin:${PREFIX:-/data/data/com.termux/files/usr}/bin/applets:$PATH"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_FILE="$PROJECT_DIR/data/start-all.log"
API_PORT="${API_PORT:-8081}"
PANEL_PORT="${PANEL_PORT:-8090}"

MODE="start"
case "${1:-}" in
    --status)  MODE="status" ;;
    --restart) MODE="restart" ;;
    "")        ;;
    *) echo "usage: $0 [--status|--restart]" >&2; exit 2 ;;
esac

mkdir -p "$PROJECT_DIR/data"

# Everything also goes to a file, because when this runs from a RUN_COMMAND intent there is no
# terminal to read: the app shows the tail of this log instead.
log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" | tee -a "$LOG_FILE"
}
say() { printf '\n\033[1m%s\033[0m\n' "$1" | tee -a "$LOG_FILE"; }
ok()  { printf '  \033[32m✓\033[0m %s\n' "$1" | tee -a "$LOG_FILE"; }
no()  { printf '  \033[36m·\033[0m %s\n' "$1" | tee -a "$LOG_FILE"; }
bad() { printf '  \033[31m✗\033[0m %s\n' "$1" | tee -a "$LOG_FILE"; }

# bash's /dev/tcp; the only port probe that needs nothing installed.
port_open() {
    (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null && { exec 3<&- 3>&- 2>/dev/null; return 0; }
    return 1
}

wait_for_port() {
    local port="$1" seconds="$2" i=0
    while [ "$i" -lt "$seconds" ]; do
        port_open "$port" && return 0
        sleep 1
        i=$((i + 1))
    done
    return 1
}

alive_from_pidfile() {
    local file="$1" pid
    [ -f "$file" ] || return 1
    pid=$(cat "$file" 2>/dev/null || true)
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

# --------------------------------------------------------------------------- status

if [ "$MODE" = "status" ]; then
    say "Service status"
    if port_open "$API_PORT"; then ok "server   listening on $API_PORT"; else bad "server   not listening on $API_PORT"; fi
    if alive_from_pidfile "$PROJECT_DIR/data/bot.pid"; then
        ok "bot      pid $(cat "$PROJECT_DIR/data/bot.pid")"
    elif pgrep -f "$PROJECT_DIR/bot/bot.py" >/dev/null 2>&1; then
        ok "bot      running (pid file stale)"
    else
        bad "bot      not running"
    fi
    if port_open "$PANEL_PORT"; then ok "panel    listening on $PANEL_PORT"; else bad "panel    not listening on $PANEL_PORT"; fi
    printf '\n'
    exit 0
fi

# --------------------------------------------------------------------------- restart

if [ "$MODE" = "restart" ]; then
    say "Stopping everything"
    bash "$PROJECT_DIR/control/run-panel.sh" stop  2>&1 | tee -a "$LOG_FILE" | sed 's/^/  /'
    bash "$PROJECT_DIR/scripts/run-bot.sh" --stop  2>&1 | tee -a "$LOG_FILE" | sed 's/^/  /'
    bash "$PROJECT_DIR/scripts/run-server.sh" stop 2>&1 | tee -a "$LOG_FILE" | sed 's/^/  /'
    sleep 2
fi

# --------------------------------------------------------------------------- start

say "Starting services"
log "start-all: mode=$MODE"

# --- 1. the self-hosted Bot API server -------------------------------------------------------
if port_open "$API_PORT"; then
    ok "server   already listening on $API_PORT"
else
    no "server   starting…"
    bash "$PROJECT_DIR/scripts/run-server.sh" start >>"$LOG_FILE" 2>&1 || true
    if wait_for_port "$API_PORT" 40; then
        ok "server   listening on $API_PORT"
    else
        # Not fatal: with TELEGRAM_LOCAL=1 the bot will report the problem itself, and the panel
        # is still worth starting so the user can see what happened.
        bad "server   did not start within 40s - the bot will use the public 50 MB API"
    fi
fi

# --- 2. the bot ------------------------------------------------------------------------------
if alive_from_pidfile "$PROJECT_DIR/data/bot.pid" || pgrep -f "$PROJECT_DIR/bot/bot.py" >/dev/null 2>&1; then
    ok "bot      already running"
else
    no "bot      starting…"
    bash "$PROJECT_DIR/scripts/run-bot.sh" --background >>"$LOG_FILE" 2>&1 || true
    # run-bot.sh waits ~5 s internally; this is the belt to its braces.
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        if alive_from_pidfile "$PROJECT_DIR/data/bot.pid"; then break; fi
        sleep 1
    done
    if alive_from_pidfile "$PROJECT_DIR/data/bot.pid"; then
        ok "bot      pid $(cat "$PROJECT_DIR/data/bot.pid")"
    else
        bad "bot      did not start - see $PROJECT_DIR/data/bot.log"
    fi
fi

# --- 3. the control panel --------------------------------------------------------------------
if port_open "$PANEL_PORT"; then
    ok "panel    already listening on $PANEL_PORT"
else
    no "panel    starting…"
    bash "$PROJECT_DIR/control/run-panel.sh" start >>"$LOG_FILE" 2>&1 || true
    if wait_for_port "$PANEL_PORT" 20; then
        ok "panel    listening on $PANEL_PORT"
    else
        bad "panel    did not start - see $PROJECT_DIR/data/panel.log"
    fi
fi

printf '\n' | tee -a "$LOG_FILE"
log "start-all: done"

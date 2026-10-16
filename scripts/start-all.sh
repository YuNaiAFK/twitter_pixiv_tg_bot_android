#!/data/data/com.termux/files/usr/bin/bash
# Start everything this project needs, in dependency order: server, alist, bot, panel.
#
#   bash scripts/start-all.sh            # start whatever is not already up
#   bash scripts/start-all.sh --status   # report only, change nothing
#   bash scripts/start-all.sh --restart  # stop and start everything
#   bash scripts/start-all.sh --stop     # stop everything, panel last
#
# **This exists so that nothing needs to be typed by hand.** Before it, the panel had to be
# started from a terminal, and the panel is what the phone app talks to - so the app could not be
# used until someone had opened Termux and run a command. The app now sends
# `com.termux.RUN_COMMAND` with this script (see enable-external-apps.sh), which closes that loop.
#
# Order matters and each step is waited for:
#
#   server  the bot is configured with TELEGRAM_LOCAL=1, so it expects http://127.0.0.1:8081
#   alist   the local image host the bot publishes gallery images through; it has no dependencies
#           of its own, but it must be up before the bot serves a link
#   bot     after the server, or it fails its startup probe and falls back to the 50 MB API
#   panel   last, because it is what the app polls; starting it first would let the app see a
#           panel whose buttons then fail
#
# `--stop` reverses that, for the mirror-image reason: the bot is stopped before the server it
# depends on, and the panel goes last so the app keeps a control surface until the very end.
#
# Every step is idempotent: run-server.sh and run-bot.sh already detect a live instance, and the
# panel does the same, so a second run reports "already running" rather than starting duplicates.

set -u
export PATH="${PREFIX:-/data/data/com.termux/files/usr}/bin:${PREFIX:-/data/data/com.termux/files/usr}/bin/applets:$PATH"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_FILE="$PROJECT_DIR/data/start-all.log"
API_PORT="${API_PORT:-8081}"
PANEL_PORT="${PANEL_PORT:-8090}"
ALIST_PORT="${ALIST_PORT:-5244}"

MODE="start"
case "${1:-}" in
    --status)  MODE="status" ;;
    --restart) MODE="restart" ;;
    --stop)    MODE="stop" ;;
    "")        ;;
    *) echo "usage: $0 [--status|--restart|--stop]" >&2; exit 2 ;;
esac

# A marker, so a start cannot race a stop that is still running.
#
# **This is not theoretical.** `--stop` takes tens of seconds - `run-server.sh stop` waits for the
# proot container to shut down - and its last act is to stop the panel. Starting again while that
# is in flight produces this, which was seen for real:
#
#     00:57:20  start-all: done        <- the start finished, panel up
#     00:57:26  start-all: stopped     <- the stop finished and killed it
#
# The user's view is the worst one: press 全部關閉, change your mind, press 一鍵啟動服務, and
# everything comes up and then silently disappears. Whichever command got there last won.
#
# The stopping side writes its pid here first and removes it when it is done. The starting side
# waits for it to go. If the pid is gone but the file remains - a stop that was killed, or a
# reboot - the marker is stale and is removed rather than waited on forever.
SHUTDOWN_MARKER="$PROJECT_DIR/data/.shutting-down"

shutdown_in_progress() {
    [ -f "$SHUTDOWN_MARKER" ] || return 1
    local pid
    pid=$(cat "$SHUTDOWN_MARKER" 2>/dev/null || true)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        return 0
    fi
    rm -f "$SHUTDOWN_MARKER"
    return 1
}

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
    if port_open "$ALIST_PORT"; then ok "alist    listening on $ALIST_PORT"; else bad "alist    not listening on $ALIST_PORT"; fi
    if port_open "$PANEL_PORT"; then ok "panel    listening on $PANEL_PORT"; else bad "panel    not listening on $PANEL_PORT"; fi
    printf '\n'
    exit 0
fi

# --------------------------------------------------------------------------- stop

if [ "$MODE" = "stop" ]; then
    # Claim the marker before touching anything, so a start that begins a moment from now sees it.
    # `$$` is this shell's pid, which is what shutdown_in_progress checks for liveness.
    printf '%s\n' "$$" > "$SHUTDOWN_MARKER"
    # Removed on every exit path, including Ctrl-C and a failure partway, so a crash cannot leave
    # a marker that blocks every future start.
    trap 'rm -f "$SHUTDOWN_MARKER"' EXIT INT TERM

    say "Stopping everything"
    log "start-all: stopping"

    # bot first: it is the one holding a Telegram poll, and stopping it before the server it
    # talks to avoids a burst of connection errors in its log as the server disappears.
    no "bot      stopping…"
    bash "$PROJECT_DIR/scripts/run-bot.sh" --stop 2>&1 | tee -a "$LOG_FILE" | sed 's/^/  /'

    no "alist    stopping…"
    bash "$PROJECT_DIR/scripts/run-alist.sh" stop 2>&1 | tee -a "$LOG_FILE" | sed 's/^/  /'

    no "server   stopping…"
    bash "$PROJECT_DIR/scripts/run-server.sh" stop 2>&1 | tee -a "$LOG_FILE" | sed 's/^/  /'

    # The wake lock was taken for the bot and the server; with both gone it only drains battery.
    if command -v termux-wake-unlock >/dev/null 2>&1; then
        termux-wake-unlock 2>/dev/null && no "wake lock released" || true
    fi

    # **The panel goes last, and after this command has had time to return.**
    #
    # Whatever asked for the shutdown is almost certainly the panel's own HTTP API - the phone
    # app's "stop everything" button - so killing it in the same breath would break the connection
    # before the response was sent, and the app would report a failure for an action that worked.
    # The caller is expected to fire this detached and read the reply first; the sleep here is the
    # belt to that braces, because a caller that does not detach still gets a clean answer.
    no "panel    stopping in 2s…"
    sleep 2
    bash "$PROJECT_DIR/control/run-panel.sh" stop 2>&1 | tee -a "$LOG_FILE" | sed 's/^/  /'

    printf '\n' | tee -a "$LOG_FILE"
    log "start-all: stopped"
    exit 0
fi

# --------------------------------------------------------------------------- restart

if [ "$MODE" = "restart" ]; then
    say "Stopping everything"
    bash "$PROJECT_DIR/control/run-panel.sh" stop  2>&1 | tee -a "$LOG_FILE" | sed 's/^/  /'
    bash "$PROJECT_DIR/scripts/run-bot.sh" --stop  2>&1 | tee -a "$LOG_FILE" | sed 's/^/  /'
    bash "$PROJECT_DIR/scripts/run-server.sh" stop 2>&1 | tee -a "$LOG_FILE" | sed 's/^/  /'
    bash "$PROJECT_DIR/scripts/run-alist.sh" stop  2>&1 | tee -a "$LOG_FILE" | sed 's/^/  /'
    sleep 2
fi

# --------------------------------------------------------------------------- start

# Wait out a stop that is still running, rather than starting into it and being killed by it.
# The timeout is generous because `run-server.sh stop` waits for a proot container to come down,
# which has been seen to take half a minute on this phone.
if shutdown_in_progress; then
    say "A shutdown is still running"
    no "waiting for it to finish before starting…"
    waited=0
    while shutdown_in_progress && [ "$waited" -lt 120 ]; do
        sleep 2
        waited=$((waited + 2))
        if [ $((waited % 10)) -eq 0 ]; then
            no "  still waiting (${waited}s)"
        fi
    done
    if shutdown_in_progress; then
        bad "the shutdown did not finish within 120s; starting anyway"
        rm -f "$SHUTDOWN_MARKER"
    else
        ok "the shutdown finished after ${waited}s"
    fi
    printf '\n'
fi

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

# --- 2. AList, the local image host ----------------------------------------------------------
# Before the bot, because the bot writes gallery images into it and hands out the URLs. Not fatal
# if it fails: a gallery can still be read through Telegraph with e-hentai's own links, and the
# panel is worth starting so the failure is visible.
if port_open "$ALIST_PORT"; then
    ok "alist    already listening on $ALIST_PORT"
else
    no "alist    starting…"
    bash "$PROJECT_DIR/scripts/run-alist.sh" start >>"$LOG_FILE" 2>&1 || true
    if wait_for_port "$ALIST_PORT" 30; then
        ok "alist    listening on $ALIST_PORT"
    else
        bad "alist    did not start - see $PROJECT_DIR/data/alist.log"
    fi
fi

# --- 3. the bot ------------------------------------------------------------------------------
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

# --- 4. the control panel --------------------------------------------------------------------
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

#!/data/data/com.termux/files/usr/bin/bash
# Report the state of the log, and remove the leftover traceback dumps.
#
# The diagnostic is off, so nothing new is being written - but truncating to the last 40 KB kept
# twenty-five of the old dumps, and they are now the only thing visible in the app's log pane. Each
# one is a full stack of every thread, identical to the one before it, so they hide whatever the log
# is actually trying to say.
#
# Removed by matching the dump's shape rather than by line count: a dump starts with "Timeout
# (0:01:00)!" and continues with "Thread 0x..." and indented frames. Blanking those lines leaves the
# real log entries in order, which is what makes the tail readable again.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
LOG="$HOME/twitter_pixiv_tg_bot/data/bot.log"
ENV_FILE="$HOME/twitter_pixiv_tg_bot/.env"
OUT="$HOME/twitter_pixiv_tg_bot/data/log-clean.txt"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo

    echo "--- the diagnostic setting ---"
    grep -n 'DEBUG_TRACEBACK' "$ENV_FILE" | sed 's/^/  /'
    echo

    echo "--- the log before ---"
    echo "  bytes: $(wc -c < "$LOG")"
    echo "  lines: $(wc -l < "$LOG")"
    echo "  'Timeout (' dumps: $(grep -c 'Timeout (' "$LOG" 2>/dev/null || echo 0)"
    echo "  'Thread 0x' headers: $(grep -c 'Thread 0x' "$LOG" 2>/dev/null || echo 0)"
    echo

    # Drop the dump blocks. An awk state machine: entering on the Timeout line, leaving when a line
    # does not look like part of a stack, so a genuine traceback from an exception is untouched -
    # those do not begin with this marker.
    awk '
        /^Timeout \(/ { skip = 1; next }
        skip && (/^Thread 0x/ || /^  File "/ || /^    / || /^$/) { next }
        { skip = 0; print }
    ' "$LOG" > "$LOG.clean"

    echo "--- the log after ---"
    echo "  bytes: $(wc -c < "$LOG.clean")"
    echo "  lines: $(wc -l < "$LOG.clean")"
    echo "  'Timeout (' dumps: $(grep -c 'Timeout (' "$LOG.clean" 2>/dev/null || echo 0)"
    echo

    # Only replace when it actually got smaller, so a bug here cannot eat the log.
    if [ -s "$LOG.clean" ] && [ "$(wc -c < "$LOG.clean")" -lt "$(wc -c < "$LOG")" ]; then
        cp "$LOG" "$LOG.bak"
        mv "$LOG.clean" "$LOG"
        echo "  replaced (backup at $(basename "$LOG").bak)"
    else
        rm -f "$LOG.clean"
        echo "  left alone - nothing to remove, or the result was not smaller"
    fi
    echo

    echo "--- what the log says now ---"
    tail -12 "$LOG" | sed 's/^/  /'
} > "$OUT" 2>&1

echo "written to $OUT"

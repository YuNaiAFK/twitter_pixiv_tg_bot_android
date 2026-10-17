#!/data/data/com.termux/files/usr/bin/bash
# Put the phone's VERSION.properties in step, and turn off the hang diagnostic.
#
# Two things that had outlived their purpose:
#
#   VERSION.properties was 1.3.1 on the phone while the app was 1.5. The panel reads that file, so
#   it reported the old version - and the version is displayed next to the app's own precisely so a
#   mismatch is visible. It was working; the file was just never pushed.
#
#   DEBUG_TRACEBACK_SECONDS=60 was added to catch a hang that had both threads idle with no Python
#   stack to show. It did its job - the dumps are what identified the waiting threads - and has been
#   firing every sixty seconds since, writing a full stack of every thread each time. The log had
#   grown to megabytes of the same idle thread.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
PROJECT="$HOME/twitter_pixiv_tg_bot"
OUT="$PROJECT/data/tidy.txt"
LOG="$PROJECT/data/bot.log"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo

    echo "--- VERSION.properties ---"
    grep '^version' "$PROJECT/VERSION.properties" | sed 's/^/  before: /'
    echo

    echo "--- the hang diagnostic ---"
    if grep -q '^DEBUG_TRACEBACK_SECONDS=' "$PROJECT/.env"; then
        # Commented out rather than deleted: the setting is worth keeping visible, because the next
        # time something hangs it is the first thing to turn back on.
        sed -i 's|^DEBUG_TRACEBACK_SECONDS=|# DEBUG_TRACEBACK_SECONDS=|' "$PROJECT/.env"
        echo "  commented out (was: $(grep '^# DEBUG_TRACEBACK_SECONDS=' "$PROJECT/.env" | cut -d= -f2))"
    else
        echo "  already off"
    fi
    echo

    echo "--- the log ---"
    if [ -f "$LOG" ]; then
        before=$(wc -c < "$LOG")
        echo "  before: $before bytes"
        # Truncated rather than deleted: an open file handle keeps writing at the old offset if the
        # inode is replaced, and the tail is what tells us whether the restart worked.
        tail -c 40000 "$LOG" > "$LOG.trim"
        mv "$LOG.trim" "$LOG"
        after=$(wc -c < "$LOG")
        echo "  after:  $after bytes (kept the last 40000)"
    else
        echo "  no log"
    fi
    echo

    echo "--- how much of the log was the diagnostic ---"
    if [ -f "$LOG" ]; then
        echo "  occurrences of 'Timeout (' in the kept tail: $(grep -c 'Timeout (' "$LOG" 2>/dev/null || echo 0)"
    fi
} > "$OUT" 2>&1

echo "written to $OUT"

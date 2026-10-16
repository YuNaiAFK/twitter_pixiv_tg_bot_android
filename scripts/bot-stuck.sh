#!/data/data/com.termux/files/usr/bin/bash
# The bot stopped logging six minutes ago in the middle of a sweep, and the sweep progress lines
# never appeared. Is it working, waiting on the network, or deadlocked?
#
# A stuck thread is the possibility that matters: the R2 upload runs in a worker thread pool, and if
# something in that path holds a lock or a connection that the rest of the parse needs, the symptom
# would look exactly like this - a log that stops mid-operation with the process still alive.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
OUT="$HOME/twitter_pixiv_tg_bot/data/bot-stuck.txt"
BASE="$HOME/twitter_pixiv_tg_bot"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo

    PID=$(cat "$BASE/data/bot.pid" 2>/dev/null || echo "")
    echo "--- pid file says: ${PID:-(none)} ---"
    if [ -n "$PID" ] && [ -d "/proc/$PID" ]; then
        echo "  process exists"
        cat "/proc/$PID/stat" 2>/dev/null | awk '{print "  state:", $3, " threads:", $20}'
        echo "  threads: $(ls /proc/$PID/task 2>/dev/null | wc -l | tr -d ' ')"
        echo "  cpu times: $(awk '{print "utime="$14, "stime="$15}' /proc/$PID/stat 2>/dev/null)"
        echo
        echo "  --- its wchan (what it is waiting on) ---"
        echo "    main: $(cat /proc/$PID/wchan 2>/dev/null)"
    else
        echo "  process does not exist - the bot died"
        echo
        echo "  --- last 30 lines of the log ---"
        tail -30 "$BASE/data/bot.log" | sed 's/^/    /'
        exit 0
    fi
    echo

    echo "--- is the bot still writing to the log? ---"
    before=$(wc -c < "$BASE/data/bot.log" 2>/dev/null)
    sleep 8
    after=$(wc -c < "$BASE/data/bot.log" 2>/dev/null)
    echo "  log size: $before -> $after  ($((after - before)) bytes in 8s)"
    echo

    echo "--- the python process tree ---"
    ps -ef 2>/dev/null | grep -E "bot/bot.py|run-bot" | grep -v grep | sed 's/^/  /'
    echo

    echo "--- how many sockets does it hold, and in what state ---"
    if [ -n "$PID" ]; then
        echo "  tcp sockets: $(cat /proc/$PID/net/tcp 2>/dev/null | wc -l | tr -d ' ')"
        echo "  --- established connections by remote port (top 8) ---"
        awk 'NR>1 {split($3,a,":"); print strtonum("0x" a[2])}' /proc/$PID/net/tcp 2>/dev/null \
            | sort | uniq -c | sort -rn | head -8 | sed 's/^/    /'
    fi
    echo

    echo "--- any thread stack hints: what files does it have open ---"
    if [ -n "$PID" ]; then
        echo "  open files: $(ls /proc/$PID/fd 2>/dev/null | wc -l | tr -d ' ')"
        ls -l /proc/$PID/fd 2>/dev/null | grep -oE '/[^ ]+$' | grep -E 'socket|log|db|cache' \
            | sort | uniq -c | sort -rn | head -8 | sed 's/^/    /'
    fi
    echo

    echo "--- last 20 log lines ---"
    tail -20 "$BASE/data/bot.log" | sed 's/^/  /'
} > "$OUT" 2>&1

echo "written to $OUT"

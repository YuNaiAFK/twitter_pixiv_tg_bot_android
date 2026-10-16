#!/data/data/com.termux/files/usr/bin/bash
# The bot is genuinely stuck: the bucket is empty and the log has not moved in minutes.
#
# What is needed is which await it is sitting on. Without py-spy, the accessible evidence is the
# process's own sockets - /proc/PID/fd holds a socket inode for each open connection, and
# /proc/net/tcp maps that inode to a local and remote address and a state. Putting the two together
# says exactly what it opened and never got an answer from.
#
# The thread count and each thread's wchan are included, because a single blocked thread among many
# is a different fault from the whole process being idle.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
OUT="$HOME/twitter_pixiv_tg_bot/data/socket-probe.txt"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    PID=$(cat "$HOME/twitter_pixiv_tg_bot/data/bot.pid" 2>/dev/null)
    echo "  pid: ${PID:-(none)}"
    if [ -z "$PID" ] || [ ! -d "/proc/$PID" ]; then
        echo "  the process is gone"
        exit 0
    fi
    echo

    echo "--- thread count and per-thread wchan ---"
    n=0
    for task in /proc/$PID/task/*; do
        n=$((n + 1))
        tid=$(basename "$task")
        printf '  tid %-8s wchan=%s\n' "$tid" "$(cat "$task/wchan" 2>/dev/null)"
    done
    echo "  total threads: $n"
    echo

    echo "--- socket inodes this process holds ---"
    sockets=$(ls -l /proc/$PID/fd 2>/dev/null | grep -oE 'socket:\[[0-9]+\]' | grep -oE '[0-9]+' | sort -u)
    if [ -z "$sockets" ]; then
        echo "  (none)"
    else
        echo "$sockets" | sed 's/^/  inode /'
    fi
    echo

    # /proc/net/tcp lists every socket in the namespace as:
    #   sl local_address rem_address st ... inode
    # Addresses are hex, little-endian per byte pair, so 0100007F is 127.0.0.1.
    decode() {
        printf '%s' "$1" | awk '{
            split($0, a, ":");
            ip = a[1];
            port = strtonum("0x" a[2]);
            printf "%d.%d.%d.%d:%d",
                strtonum("0x" substr(ip,7,2)),
                strtonum("0x" substr(ip,5,2)),
                strtonum("0x" substr(ip,3,2)),
                strtonum("0x" substr(ip,1,2)),
                port;
        }'
    }

    state_name() {
        case "$1" in
            01) echo ESTABLISHED ;;
            02) echo SYN_SENT ;;
            06) echo TIME_WAIT ;;
            08) echo CLOSE_WAIT ;;
            *)  echo "state=$1" ;;
        esac
    }

    echo "--- the connections behind those inodes ---"
    for inode in $sockets; do
        line=$(grep -i " $inode " /proc/net/tcp /proc/net/tcp6 2>/dev/null | head -1)
        if [ -n "$line" ]; then
            local_addr=$(echo "$line" | awk '{print $2}')
            rem_addr=$(echo "$line" | awk '{print $3}')
            st=$(echo "$line" | awk '{print $4}')
            printf '  %-22s -> %-22s %s\n' "$(decode "$local_addr")" "$(decode "$rem_addr")" "$(state_name "$st")"
        fi
    done
    echo

    echo "--- what the bot's HTTP client is pointed at ---"
    grep -E '^(TELEGRAM_API_BASE|TELEGRAM_LOCAL|BOT_PROXY)=' \
        "$HOME/twitter_pixiv_tg_bot/.env" 2>/dev/null | sed 's/^/  /'
    echo

    echo "--- is the local Bot API server answering? ---"
    if timeout 6 bash -c 'exec 3<>/dev/tcp/127.0.0.1/8081' 2>/dev/null; then
        echo "  8081 accepts a connection"
    else
        echo "  8081 does NOT accept a connection"
    fi
    echo

    echo "--- log size, before and after 10s ---"
    before=$(wc -c < "$HOME/twitter_pixiv_tg_bot/data/bot.log" 2>/dev/null)
    sleep 10
    after=$(wc -c < "$HOME/twitter_pixiv_tg_bot/data/bot.log" 2>/dev/null)
    echo "  $before -> $after"
} > "$OUT" 2>&1

echo "written to $OUT"

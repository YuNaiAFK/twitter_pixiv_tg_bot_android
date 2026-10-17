#!/data/data/com.termux/files/usr/bin/bash
# What buttons does the deployed bot.py actually define?
#
# Written as a script because every attempt to grep for the callback strings from PowerShell failed:
# the callback pattern contains "eh|view", and a pipe is a PowerShell operator, so the argument was
# split and the grep never ran.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
OUT="$HOME/twitter_pixiv_tg_bot/data/button-check.txt"
BOT="$HOME/twitter_pixiv_tg_bot/bot/bot.py"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo "  bot.py: $(wc -c < "$BOT") bytes"
    echo

    echo "--- the gallery keyboard's buttons ---"
    grep -n 'InlineKeyboardButton("' "$BOT" | grep -E 'Telegraph|歸檔|取消' | sed 's/^/  /'
    echo

    echo "--- callback modes present in the file ---"
    for mode in view orig zip1280 ziporig; do
        count=$(grep -c "eh|$mode|" "$BOT" 2>/dev/null || echo 0)
        case "$mode" in
            orig)    want="0 (removed)" ;;
            view)    want="at least 1" ;;
            zip1280) want="at least 1" ;;
            ziporig) want="at least 1" ;;
        esac
        printf '  eh|%-9s %s occurrence(s)   expected: %s\n' "$mode" "$count" "$want"
    done
    echo

    echo "--- the allowlist ---"
    grep -n 'if mode not in' "$BOT" | sed 's/^/  /'
    echo

    echo "--- the dispatch ---"
    grep -n 'if mode == "view"' "$BOT" | sed 's/^/  /'
    echo

    echo "--- the label map ---"
    grep -n -A5 'label = {' "$BOT" | head -8 | sed 's/^/  /'
} > "$OUT" 2>&1

echo "written to $OUT"

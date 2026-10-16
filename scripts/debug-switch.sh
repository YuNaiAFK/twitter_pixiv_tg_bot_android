#!/data/data/com.termux/files/usr/bin/bash
# Set the diagnostic switch and confirm the new code is actually installed.
#
# Two things to verify rather than assume: that DEBUG_TRACEBACK_SECONDS is in .env exactly once, and
# that the installed bot.py contains the function the switch drives. An install that silently did
# nothing is exactly the failure the hash check in install-staged.sh exists to catch, and a hash that
# looks the same as the previous version is worth looking at directly.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"

PROJECT_DIR="$HOME/twitter_pixiv_tg_bot"
ENV_FILE="$PROJECT_DIR/.env"
OUT="$PROJECT_DIR/data/debug-switch.txt"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo

    echo "--- is the new code in the installed bot.py? ---"
    if grep -q "def enable_thread_dumps" "$PROJECT_DIR/bot/bot.py"; then
        echo "  enable_thread_dumps: present"
    else
        echo "  enable_thread_dumps: MISSING - the install did not take"
    fi
    if grep -q "enable_thread_dumps()" "$PROJECT_DIR/bot/bot.py"; then
        echo "  called from main():  present"
    fi
    echo "  bot.py size: $(wc -c < "$PROJECT_DIR/bot/bot.py") bytes"
    echo

    echo "--- setting DEBUG_TRACEBACK_SECONDS, exactly once ---"
    grep -v '^DEBUG_TRACEBACK_SECONDS=' "$ENV_FILE" > "$ENV_FILE.tmp" 2>/dev/null \
        && mv "$ENV_FILE.tmp" "$ENV_FILE"
    printf 'DEBUG_TRACEBACK_SECONDS=60\n' >> "$ENV_FILE"
    echo "  lines matching: $(grep -c '^DEBUG_TRACEBACK_SECONDS=' "$ENV_FILE")"
    grep '^DEBUG_TRACEBACK_SECONDS=' "$ENV_FILE" | sed 's/^/  /'
    echo

    echo "--- and confirm python can parse the installed file ---"
    if python -m py_compile "$PROJECT_DIR/bot/bot.py" 2>&1; then
        echo "  py_compile: ok"
    else
        echo "  py_compile: FAILED"
    fi
} > "$OUT" 2>&1

echo "written to $OUT"

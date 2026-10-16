#!/data/data/com.termux/files/usr/bin/bash
# Which of the recent bot.py changes are actually on the device?
#
# The install bug found a moment ago wrote a stale staged bot.py to the project root instead of
# bot/bot.py, and reported "ok bot.py" while doing it. Every bot.py deploy through that name was
# therefore a no-op. The only way to know what the device is really running is to look for the
# functions each change introduced.
#
# Each line names a change and the thing it added, so a missing one is unambiguous.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
OUT="$HOME/twitter_pixiv_tg_bot/data/deployed-check.txt"
BOT="$HOME/twitter_pixiv_tg_bot/bot/bot.py"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo "  bot.py: $(wc -c < "$BOT") bytes"
    echo

    printf '%-46s %s\n' "change" "present?"
    printf '%-46s %s\n' "----------------------------------------------" "--------"

    check() {
        local label="$1" pattern="$2"
        if grep -q "$pattern" "$BOT"; then
            printf '  %-44s YES\n' "$label"
        else
            printf '  %-44s *** NO ***\n' "$label"
        fi
    }

    check "group gate (@bot required)"      "def gate_undirected_group_commands"
    check "regenerate cache per gallery"    "def regenerate_cache_key"
    check "telegraph edit in place"         "def edit_telegraph_page"
    check "telegraph page reuse"            "def cached_telegraph_entry"
    check "image verification (page read)"  "def telegraph_page_images"
    check "R2 cache helpers"                "def cached_r2_urls"
    check "R2 upload host"                  "async def host_on_r2"
    check "R2 call site"                    "embed = await host_on_r2"
    check "thread dumps (diagnostic)"       "def enable_thread_dumps"
    echo

    echo "--- and the junk file the bug created ---"
    if [ -f "$HOME/twitter_pixiv_tg_bot/bot.py" ]; then
        echo "  *** $HOME/twitter_pixiv_tg_bot/bot.py exists - that is the misplaced install ***"
        echo "      size: $(wc -c < "$HOME/twitter_pixiv_tg_bot/bot.py") bytes"
    else
        echo "  no stray bot.py at the project root (correct)"
    fi
    echo

    echo "--- the debug switch ---"
    grep '^DEBUG_TRACEBACK_SECONDS=' "$HOME/twitter_pixiv_tg_bot/.env" | sed 's/^/  /'
    tail -60 "$HOME/twitter_pixiv_tg_bot/data/bot.log" | grep -c "已啟用執行緒堆疊" \
        | sed 's/^/  activation lines in the last 60 log lines: /'
} > "$OUT" 2>&1

echo "written to $OUT"

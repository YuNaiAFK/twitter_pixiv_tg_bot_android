#!/data/data/com.termux/files/usr/bin/bash
# What the phone can reach, and what is already using which port - the facts needed before
# installing AList.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
OUT="$HOME/twitter_pixiv_tg_bot/data/alist-precheck.txt"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo

    echo "--- architecture and space ---"
    echo "  arch:  $(uname -m)"
    df -h "$HOME" | tail -1 | sed 's/^/  home:  /'
    echo

    echo "--- proxy from .env ---"
    grep -E 'PROXY' "$HOME/twitter_pixiv_tg_bot/.env" 2>/dev/null | sed 's/^/  /'
    echo

    echo "--- ports already listening ---"
    for port in 8081 8090 5244; do
        if command -v ss >/dev/null 2>&1; then
            line=$(ss -tln 2>/dev/null | grep ":$port ")
        else
            line=$(netstat -tln 2>/dev/null | grep ":$port ")
        fi
        if [ -n "$line" ]; then
            echo "  $port  IN USE"
        else
            echo "  $port  free"
        fi
    done
    echo

    echo "--- can we reach the alist release? ---"
    DIRECT=$(curl -s -o /dev/null -w '%{http_code}' --max-time 12 -I \
        https://github.com/AlistGo/alist/releases/latest 2>/dev/null)
    echo "  direct (no proxy): HTTP $DIRECT"
    PROXIED=$(curl -s -o /dev/null -w '%{http_code}' --max-time 12 \
        -x http://127.0.0.1:10808 -I \
        https://github.com/AlistGo/alist/releases/latest 2>/dev/null)
    echo "  via 127.0.0.1:10808: HTTP $PROXIED"
    echo

    echo "--- is alist already installed? ---"
    if [ -x "$HOME/alist/alist" ]; then
        echo "  yes: $HOME/alist/alist"
        "$HOME/alist/alist" version 2>&1 | sed 's/^/  /'
    else
        echo "  no"
    fi
    echo

    echo "--- what is in ~ ? ---"
    ls -la "$HOME" 2>/dev/null | head -20 | sed 's/^/  /'
} > "$OUT" 2>&1

echo "written to $OUT"

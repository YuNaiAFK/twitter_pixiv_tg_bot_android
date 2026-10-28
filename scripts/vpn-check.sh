#!/data/data/com.termux/files/usr/bin/bash
# Does v2rayNG start itself at boot, and is its VPN actually connected right now?
#
# This is the real fix for the bot dying after a reboot: wait_for_telegram now makes the bot tolerate
# a late VPN, but a VPN that never comes up means the bot waits fifteen minutes and then gives up.
# v2rayNG has an "auto start on boot" preference, and if it is off, no amount of retrying helps.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
OUT="$HOME/twitter_pixiv_tg_bot/data/vpn-check.txt"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo

    echo "--- v2rayNG preference files ---"
    PREFS=/data/data/com.v2ray.ang/shared_prefs
    if [ -d "$PREFS" ]; then
        ls -la "$PREFS" 2>/dev/null | sed 's/^/  /'
    else
        echo "  cannot read $PREFS (needs root)"
    fi
    echo

    echo "--- preferences mentioning boot or startup ---"
    if [ -r "$PREFS" ]; then
        for f in "$PREFS"/*.xml; do
            [ -f "$f" ] || continue
            hits=$(grep -i -E "boot|startup|auto.?start|reboot" "$f" 2>/dev/null)
            if [ -n "$hits" ]; then
                echo "  $(basename "$f"):"
                echo "$hits" | sed 's/^/    /'
            fi
        done
    fi
    echo

    echo "--- every boolean preference (the setting is one of these) ---"
    if [ -r "$PREFS" ]; then
        for f in "$PREFS"/*.xml; do
            [ -f "$f" ] || continue
            echo "  $(basename "$f"):"
            grep -o 'name="[^"]*" value="[^"]*"' "$f" 2>/dev/null | head -40 | sed 's/^/    /'
        done
    fi
    echo

    echo "--- is the VPN connected right now ---"
    if timeout 5 bash -c "exec 3<>/dev/tcp/127.0.0.1/10808" 2>/dev/null; then
        echo "  proxy port 10808: OPEN"
    else
        echo "  proxy port 10808: CLOSED"
    fi
    ip -4 addr show 2>/dev/null | grep -A1 "tun0" | sed 's/^/  /'
    echo

    echo "--- is the v2rayNG process running ---"
    ps -ef 2>/dev/null | grep -i v2ray | grep -v grep | sed 's/^/  /' || echo "  not running"
    echo

    echo "--- is it exempt from battery optimisation (Android kills it otherwise) ---"
    dumpsys deviceidle whitelist 2>/dev/null | grep -i v2ray | sed 's/^/  /' || echo "  not whitelisted"
} > "$OUT" 2>&1

echo "written to $OUT"

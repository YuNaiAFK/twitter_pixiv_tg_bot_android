#!/data/data/com.termux/files/usr/bin/bash
# Detect the phone's own proxy (v2rayNG and friends) and prove it carries traffic.
#
# Run this FROM THE TERMUX APP, not over adb: an adb-started process lands in the
# `u:r:magisk:s0` SELinux domain and every connection fails with "socket: Permission denied",
# so a proxy test from there always looks like a failure. See README.
#
# v2rayNG's defaults are SOCKS5 on 10808 and HTTP on 10809; other clients use 7890/7891.
# Both are tried as SOCKS5 and as HTTP, because guessing the wrong protocol looks exactly like
# a dead proxy.

set -u

CANDIDATES="10808 10809 7890 7891 1080 8118 8889"
PROBE_URL="https://www.google.com/generate_204"
FALLBACK_URL="https://github.com/"

say()  { printf '\n\033[1m%s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
no()   { printf '  \033[36m·\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; }

say "Looking for a local proxy"
OPEN=""
for port in $CANDIDATES; do
    if (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
        exec 3<&- 3>&- 2>/dev/null
        ok "port $port is listening"
        OPEN="$OPEN $port"
    fi
done
[ -n "$OPEN" ] || { bad "no local proxy port answers. Is the VPN switched on?"; exit 1; }

say "Testing which protocol works"
# A proxy that accepts a connection but carries nothing is worse than none, because every tool
# then hangs instead of saying so. So each candidate has to fetch something real.
FOUND_SCHEME=""
FOUND_PORT=""
for port in $OPEN; do
    for scheme in socks5 http; do
        # curl speaks both; --max-time keeps a black hole from stalling the probe.
        code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
               -x "$scheme://127.0.0.1:$port" "$PROBE_URL" 2>/dev/null || echo "000")
        if [ "$code" = "204" ] || [ "$code" = "200" ]; then
            ok "$scheme://127.0.0.1:$port  works (HTTP $code)"
            FOUND_SCHEME="$scheme"
            FOUND_PORT="$port"
            break 2
        else
            no "$scheme://127.0.0.1:$port  -> $code"
        fi
    done
done

# google.com/generate_204 is unreachable on some networks even through a working proxy, so a
# second opinion is taken before declaring failure.
if [ -z "$FOUND_SCHEME" ]; then
    say "Retrying against github.com (generate_204 may be blocked regardless)"
    for port in $OPEN; do
        for scheme in socks5 http; do
            code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 12 \
                   -x "$scheme://127.0.0.1:$port" "$FALLBACK_URL" 2>/dev/null || echo "000")
            if [ "$code" = "200" ] || [ "$code" = "301" ] || [ "$code" = "302" ]; then
                ok "$scheme://127.0.0.1:$port  works (HTTP $code)"
                FOUND_SCHEME="$scheme"
                FOUND_PORT="$port"
                break 2
            fi
        done
    done
fi

if [ -z "$FOUND_SCHEME" ]; then
    bad "a port is open but nothing got through. Check the VPN's node, or that it is in"
    bad "proxy mode rather than VPN mode (VPN mode needs no proxy setting at all)."
    exit 1
fi

say "Direct connection, for comparison"
direct=$(curl -s -o /dev/null -w '%{http_code}' --max-time 12 "$FALLBACK_URL" 2>/dev/null || echo "000")
if [ "$direct" = "200" ]; then
    ok "github.com is reachable WITHOUT the proxy too (HTTP 200)"
else
    no "github.com without the proxy: $direct  (so the proxy is needed)"
fi

say "Result"
PROXY_URL="$FOUND_SCHEME://127.0.0.1:$FOUND_PORT"
printf '  proxy   %s\n' "$PROXY_URL"
printf '\n'
printf '  Set it for this session with:\n\n'
printf '      export http_proxy=%s\n' "$PROXY_URL"
printf '      export https_proxy=%s\n' "$PROXY_URL"
printf '      export all_proxy=%s\n' "$PROXY_URL"
printf '\n'
printf '  Or make it permanent by appending those three lines to ~/.bashrc\n'

# Leave the values somewhere the installer can pick them up without re-probing.
printf '%s\n' "$PROXY_URL" > "$HOME/.proxy-url"
ok "written to ~/.proxy-url"

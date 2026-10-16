#!/data/data/com.termux/files/usr/bin/bash
# Why can curl resolve names when cloudflared cannot?
#
# cloudflared reports every lookup going to [::1]:53 with "connection refused". Go reads
# /etc/resolv.conf with its own resolver; curl and Python go through Android's netd, which does not
# use that file at all. So a resolv.conf that is wrong for Go breaks Go programs and nothing else -
# which is exactly the shape of this failure.
#
# This records what the file says, how Go behaves with each resolver, and whether a plain DNS query
# to a public server works at all from here.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
OUT="$HOME/twitter_pixiv_tg_bot/data/dns-probe.txt"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo

    echo "--- /etc/resolv.conf (what Go reads) ---"
    for f in "$PREFIX/etc/resolv.conf" /etc/resolv.conf; do
        if [ -f "$f" ]; then
            echo "  $f"
            sed 's/^/    /' "$f"
        else
            echo "  $f: does not exist"
        fi
    done
    echo

    echo "--- Android's own DNS servers ---"
    getprop 2>/dev/null | grep -iE 'net\.dns[0-9]' | sed 's/^/  /'
    echo

    echo "--- can the system resolve at all? ---"
    # getent goes through the C library, the same path curl uses.
    getent hosts api.cloudflare.com 2>&1 | head -3 | sed 's/^/  getent: /'
    curl -s -o /dev/null -w '  curl api.cloudflare.com: HTTP %{http_code} in %{time_total}s\n' \
        --max-time 15 https://api.cloudflare.com/client/v4/ips 2>&1
    echo

    echo "--- a direct query to a public resolver ---"
    for server in 1.1.1.1 8.8.8.8; do
        if command -v dig >/dev/null 2>&1; then
            r=$(dig +short +time=5 +tries=1 "@$server" api.cloudflare.com A 2>&1 | head -2 | tr '\n' ' ')
        else
            r="(dig not installed)"
        fi
        echo "  $server via dig: ${r:-no answer}"
    done
    echo

    echo "--- and a plain TCP connection to a public resolver on 53 ---"
    if timeout 5 bash -c "exec 3<>/dev/tcp/1.1.1.1/53" 2>/dev/null; then
        echo "  TCP 1.1.1.1:53 reachable"
    else
        echo "  TCP 1.1.1.1:53 NOT reachable"
    fi
    if timeout 5 bash -c "exec 3<>/dev/udp/1.1.1.1/53" 2>/dev/null; then
        echo "  UDP 1.1.1.1:53 reachable"
    else
        echo "  UDP 1.1.1.1:53 NOT reachable"
    fi
    echo

    echo "--- what Go's resolver does right now ---"
    # cloudflared --version proves the binary runs; this proves what its resolver picks.
    GODEBUG=netdns=go "$HOME/cloudflared/download/cloudflared" tunnel --help >/dev/null 2>&1 \
        && echo "  netdns=go: binary ran" || echo "  netdns=go: failed"
    echo
} > "$OUT" 2>&1

echo "written to $OUT"

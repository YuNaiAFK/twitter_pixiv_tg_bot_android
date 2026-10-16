#!/data/data/com.termux/files/usr/bin/bash
# TUN is already up (tun0, 10.10.14.1) and the edge is still unreachable, so TUN mode was never the
# problem. What the earlier probe showed is more specific:
#
#     via CONNECT through the proxy, edge :7844  -> 000     (failed)
#     via the proxy, api.cloudflare.com          -> 200     (works)
#
# Two things to establish. First, whether 7844 is really failing a CONNECT or whether the earlier
# test was malformed - curl needs -p for a non-HTTP port, and without it the request never reaches
# the proxy the way it looks like it does. Second, whether the edge serves the tunnel on 443, which
# would be a way around a blocked 7844.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
OUT="$HOME/twitter_pixiv_tg_bot/data/port-probe.txt"
PROXY="http://127.0.0.1:10808"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo

    echo "--- a plain CONNECT to the edge on 7844, verbosely ---"
    curl -v --max-time 20 -p -x "$PROXY" https://region1.v2.argotunnel.com:7844/ 2>&1 \
        | grep -iE 'CONNECT|established|refused|denied|timed|fail|error|< HTTP|Empty reply' \
        | head -8 | sed 's/^/  /'
    echo

    echo "--- and the same on 443 ---"
    curl -v --max-time 20 -p -x "$PROXY" https://region1.v2.argotunnel.com:443/ 2>&1 \
        | grep -iE 'CONNECT|established|refused|denied|timed|fail|error|< HTTP|Empty reply' \
        | head -8 | sed 's/^/  /'
    echo

    echo "--- does the control still work through the same proxy? ---"
    curl -s -o /dev/null -w '  api.cloudflare.com:443 -> %{http_code}\n' \
        --max-time 20 -x "$PROXY" https://api.cloudflare.com/client/v4/ips 2>&1
    echo

    echo "--- is 7844 blocked even without the proxy (plain TCP, TUN routing)? ---"
    for ip in 198.41.192.107 198.41.192.227; do
        for port in 7844 443; do
            if timeout 10 bash -c "exec 3<>/dev/tcp/$ip/$port" 2>/dev/null; then
                printf '  %s:%-5s connect ok\n' "$ip" "$port"
            else
                printf '  %s:%-5s FAILED\n' "$ip" "$port"
            fi
        done
    done
    echo

    echo "--- TLS on 7844 by hand: does the handshake get anywhere? ---"
    # openssl division of labour: if the handshake completes here but cloudflared reports EOF, the
    # difference is in what cloudflared asks for, not in the path.
    if command -v openssl >/dev/null 2>&1; then
        timeout 15 openssl s_client -connect 198.41.192.107:7844 -servername region1.v2.argotunnel.com \
            -brief </dev/null 2>&1 | head -8 | sed 's/^/  /'
    else
        echo "  (openssl not installed)"
    fi
} > "$OUT" 2>&1

echo "written to $OUT"

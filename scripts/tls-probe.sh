#!/data/data/com.termux/files/usr/bin/bash
# The CONNECT to the edge on 7844 succeeds through the proxy, so the path is open and the failure
# is specifically in the TLS handshake. This gets the full handshake output rather than a filtered
# summary, because the useful part is which side sends what before the EOF.
#
# cloudflared reports:  TLS handshake with edge error: EOF
# which means the server closed the connection during or just after the ClientHello.
#
# If a normal TLS client with the right server name can complete a handshake here, then the path is
# fine and cloudflared's own TLS parameters are the difference. If it cannot, the path is blocked at
# the TLS layer and no amount of cloudflared configuration will help.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
OUT="$HOME/twitter_pixiv_tg_bot/data/tls-probe.txt"
PROXY="http://127.0.0.1:10808"
EDGE="region1.v2.argotunnel.com"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo

    echo "--- full handshake through the proxy, with the edge server name ---"
    curl -v --max-time 25 -p -x "$PROXY" "https://$EDGE:7844/" 2>&1 \
        | grep -vE '^\{|^\}|^\*   Trying|Proxy-Connection|^> Host' | head -30 | sed 's/^/  /'
    echo

    echo "--- the same, without the proxy (TUN routes it) ---"
    curl -v --max-time 25 "https://$EDGE:7844/" 2>&1 \
        | grep -vE '^\{|^\}|^\*   Trying|^> Host' | head -30 | sed 's/^/  /'
    echo

    echo "--- what ALPN does the edge offer on 7844? ---"
    # cloudflared needs h2. If the edge offers something else, or nothing, that explains the EOF.
    curl -v --max-time 25 -p -x "$PROXY" --http2 "https://$EDGE:7844/" 2>&1 \
        | grep -iE 'ALPN|h2|http/2|negotiated|SSL connection|TLSv' | head -8 | sed 's/^/  /'
    echo

    echo "--- a plain TLS handshake using python, which reports the failure precisely ---"
    python - <<'PY'
import socket, ssl

HOST = "region1.v2.argotunnel.com"
for port, label in ((7844, "7844 (tunnel)"), (443, "443 (control host)")):
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    try:
        ctx.set_alpn_protocols(["h2", "http/1.1"])
    except Exception:
        pass
    try:
        with socket.create_connection((HOST, port), timeout=15) as raw:
            with ctx.wrap_socket(raw, server_hostname=HOST) as tls:
                print("  %-18s connected: %s  %s  alpn=%s" % (
                    label, tls.version(), tls.cipher()[0], tls.selected_alpn_protocol()))
    except Exception as exc:
        print("  %-18s FAILED: %s: %s" % (label, type(exc).__name__, exc))
PY
} > "$OUT" 2>&1

echo "written to $OUT"

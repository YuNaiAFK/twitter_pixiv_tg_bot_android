#!/data/data/com.termux/files/usr/bin/bash
# The edge discovery needs an SRV lookup, and the phone's proxy answers every SRV query with
# rcode=5 (REFUSED) - it is running in fake-IP mode, which rewrites A records to 198.19.x.x and
# does not implement SRV at all.
#
# So the question is whether cloudflared can be told where the edge is, skipping discovery.
# Newer builds dropped the old --edge flag, but there are related options and environment
# variables, and the config file accepts keys the CLI does not expose.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"

CHROOT_NAME="${CHROOT_NAME:-botapi}"
PROOT_BASE="$PREFIX/var/lib/proot-distro"
ROOTFS="$PROOT_BASE/containers/$CHROOT_NAME/rootfs"
OUT="$HOME/twitter_pixiv_tg_bot/data/edge-probe.txt"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo

    echo "--- every edge-related flag in the global help ---"
    proot-distro login "$CHROOT_NAME" -- /usr/local/bin/cloudflared --help 2>&1 \
        | grep -iE 'edge|region|address|addr' | sed 's/^/  /'
    echo

    echo "--- and in 'tunnel run' ---"
    proot-distro login "$CHROOT_NAME" -- /usr/local/bin/cloudflared tunnel run --help 2>&1 \
        | grep -iE '^\s+--' | grep -iE 'edge|region|protocol|ha' | sed 's/^/  /'
    echo

    echo "--- does a config file accept an edge key? ---"
    # The binary carries its own list of recognised config keys; grepping them out of the binary is
    # crude but it answers the question without guessing.
    proot-distro login "$CHROOT_NAME" -- /bin/sh -c \
        'strings /usr/local/bin/cloudflared 2>/dev/null | grep -iE "^(edge|edge-address|edge_ip|region)" | sort -u | head -20' \
        2>&1 | sed 's/^/  /'
    echo

    echo "--- environment variables it reads ---"
    proot-distro login "$CHROOT_NAME" -- /bin/sh -c \
        'strings /usr/local/bin/cloudflared 2>/dev/null | grep -oE "TUNNEL_[A-Z_]+" | sort -u | head -30' \
        2>&1 | sed 's/^/  /'
    echo

    echo "--- can DoH answer the SRV question? (over HTTPS, so it goes through the proxy) ---"
    # If the SRV answer can be obtained at all, the edge hostnames and ports are knowable. This
    # shows whether the information exists on the other side of the proxy even though plain DNS
    # refuses it.
    curl -s --max-time 20 -H 'accept: application/dns-json' \
        'https://1.1.1.1/dns-query?name=_v2-origintunneld._tcp.argotunnel.com&type=SRV' \
        2>&1 | head -c 900 | sed 's/^/  /'
    echo
    echo
    echo "--- and the A record over DoH, for comparison ---"
    curl -s --max-time 20 -H 'accept: application/dns-json' \
        'https://1.1.1.1/dns-query?name=region1.v2.argotunnel.com&type=A' \
        2>&1 | head -c 500 | sed 's/^/  /'
    echo
} > "$OUT" 2>&1

echo "written to $OUT"

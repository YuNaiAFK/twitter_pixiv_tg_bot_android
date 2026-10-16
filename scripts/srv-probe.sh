#!/data/data/com.termux/files/usr/bin/bash
# cloudflared needs an SRV lookup to find its edge, and the SRV lookup is what fails:
#
#     lookup _v2-origintunneld._tcp.argotunnel.com on 8.8.4.4:53: server misbehaving
#
# "server misbehaving" is what Go reports for a malformed or refused reply, and an intercepted DNS
# answer is the usual cause - a resolver that handles ordinary A records but mangles or drops the
# SRV type. Ordinary lookups work here (curl reaches api.cloudflare.com), so this checks the SRV
# type specifically, against several resolvers, to see whether any of them is clean.
#
# It also checks whether cloudflared can be told the edge directly, which would skip SRV discovery
# altogether - the addresses it wants are region1/region2.v2.argotunnel.com, and those are plain A
# records.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"

CHROOT_NAME="${CHROOT_NAME:-botapi}"
PROOT_BASE="$PREFIX/var/lib/proot-distro"
ROOTFS="$PROOT_BASE/containers/$CHROOT_NAME/rootfs"
OUT="$HOME/twitter_pixiv_tg_bot/data/srv-probe.txt"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo

    echo "--- the container's resolvers ---"
    cat "$ROOTFS/etc/resolv.conf" 2>&1 | sed 's/^/  /'
    echo

    echo "--- is a DNS tool available in the container? ---"
    proot-distro login "$CHROOT_NAME" -- /bin/sh -c \
        'command -v dig nslookup host getent python3 2>/dev/null | sed "s/^/  /"; echo "  ---"' 2>&1
    echo

    echo "--- python in the container, querying SRV directly ---"
    # dnspython is almost certainly absent, so this builds the query by hand. That also means it
    # cannot be fooled by a library quietly falling back to something else.
    proot-distro login "$CHROOT_NAME" -- /bin/sh -c 'python3 - <<"PY"
import socket, struct, sys

def build_srv(name):
    q = b""
    for label in name.split("."):
        if label:
            q += bytes([len(label)]) + label.encode()
    q += b"\x00"
    q += struct.pack("!HH", 33, 1)          # QTYPE=SRV, QCLASS=IN
    header = struct.pack("!HHHHHH", 0x1234, 0x0100, 1, 0, 0, 0)
    return header + q

def parse_srv(data):
    ancount = struct.unpack("!H", data[6:8])[0]
    if ancount == 0:
        return "no answers (rcode=%d)" % (data[3] & 0x0F)
    return "%d answer(s), rcode=%d" % (ancount, data[3] & 0x0F)

for server in ("8.8.8.8", "8.8.4.4", "1.1.1.1", "9.9.9.9"):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(6)
    try:
        s.sendto(build_srv("_v2-origintunneld._tcp.argotunnel.com"), (server, 53))
        data, _ = s.recvfrom(4096)
        print("  %-9s %s" % (server, parse_srv(data)))
    except Exception as exc:
        print("  %-9s FAILED: %s" % (server, type(exc).__name__))
    finally:
        s.close()
PY' 2>&1 | sed 's/^/  /'
    echo

    echo "--- and the plain A records cloudflared would use if told the edge ---"
    proot-distro login "$CHROOT_NAME" -- /bin/sh -c 'python3 - <<"PY"
import socket
for host in ("region1.v2.argotunnel.com", "region2.v2.argotunnel.com",
             "api.cloudflare.com", "update.argotunnel.com"):
    try:
        infos = socket.getaddrinfo(host, 443, socket.AF_INET)
        addrs = sorted({i[4][0] for i in infos})
        print("  %-32s %s" % (host, ", ".join(addrs[:3])))
    except Exception as exc:
        print("  %-32s FAILED: %s" % (host, type(exc).__name__))
PY' 2>&1 | sed 's/^/  /'
    echo

    echo "--- what edge flags does this cloudflared accept? ---"
    proot-distro login "$CHROOT_NAME" -- /usr/local/bin/cloudflared tunnel run --help 2>&1 \
        | grep -iE 'edge|region|protocol' | sed 's/^/  /'
} > "$OUT" 2>&1

echo "written to $OUT"

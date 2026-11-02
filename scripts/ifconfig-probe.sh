#!/data/data/com.termux/files/usr/bin/bash
# Can `ifconfig` see the tunnel from inside the Termux app's own domain?
#
# Everything under /proc/net and /sys/class/net is denied to u:r:untrusted_app_27, which is where the
# panel and every RUN_COMMAND script run. `ifconfig` ships with Termux and uses ioctl rather than those
# files, so it is the one listing that might work. If it does, the card can name the interface; if it
# does not, the card falls back to "can I reach the internet at all", which is the question the user
# actually cares about.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
OUT="$HOME/twitter_pixiv_tg_bot/data/ifconfig-probe.txt"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo "  context: $(tr -d '\0' < /proc/self/attr/current 2>/dev/null)"
    echo

    echo "--- ifconfig -a ---"
    ifconfig -a 2>&1 | head -60 | sed 's/^/  /'
    echo

    echo "--- interfaces named like a VPN ---"
    ifconfig -a 2>/dev/null | grep -E "^[a-z0-9]+" | awk -F: '{print $1}' \
        | grep -E "^(tun|utun|ppp|wg)" | sed 's/^/  /' || echo "  none"
    echo

    echo "--- ifconfig for just the tun, if it exists ---"
    ifconfig tun0 2>&1 | sed 's/^/  /'
    echo

    echo "--- TCP connect to a well-known address (the check that needs no interface list) ---"
    python - <<'PY'
import socket
import time

# The question the card is really answering: will a download work?
# 1.1.1.1:443 is a plain TCP connect with no DNS and no TLS handshake - cheap and hard to censor
# silently, since a TUN-mode VPN either carries it or does not.
for host, port, label in (("1.1.1.1", 443, "1.1.1.1:443"),
                          ("8.8.8.8", 53, "8.8.8.8:53"),
                          ("149.154.167.51", 443, "telegram DC 149.154.167.51:443")):
    started = time.perf_counter()
    try:
        with socket.create_connection((host, port), timeout=3.0):
            elapsed = (time.perf_counter() - started) * 1000
            print(f"  {label:38} OK ({elapsed:.0f} ms)")
    except OSError as exc:
        print(f"  {label:38} FAILED ({type(exc).__name__}: {exc})")
PY
    echo

    echo "--- and the interface list via python's socket module (ioctl, no /sys) ---"
    python - <<'PY'
import socket

# SIOCGIFCONF lists interfaces through an ioctl, which does not need /sys/class/net. On Linux it is
# awkward to parse in pure Python, so this only reports whether the ioctl is permitted at all.
try:
    names = socket.if_nameindex()
    print(f"  if_nameindex() -> {names}")
    vpn = [n for _, n in names if n.startswith(("tun", "utun", "ppp", "wg"))]
    print(f"  vpn-ish: {vpn}")
except Exception as exc:
    print(f"  if_nameindex() FAILED: {type(exc).__name__}: {exc}")
PY
} > "$OUT" 2>&1

echo "written to $OUT"

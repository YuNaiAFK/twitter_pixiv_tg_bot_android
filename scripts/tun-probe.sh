#!/data/data/com.termux/files/usr/bin/bash
# Can the panel see the tunnel, and what does it actually see?
#
# The panel runs as the Termux app's own uid in u:r:untrusted_app_27, not as root. /sys/class/net is
# usually world-readable, but "usually" is not a reason to assume - the whole point of the check is
# that it returns a real answer, and if the directory cannot be listed then `mode` will say "none" on
# a phone whose VPN is fine, which is the same false alarm in a new place.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
OUT="$HOME/twitter_pixiv_tg_bot/data/tun-probe.txt"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo

    echo "--- who am I ---"
    id 2>&1 | sed 's/^/  /'
    echo

    echo "--- can I list /sys/class/net ---"
    if [ -d /sys/class/net ]; then
        echo "  exists"
        ls /sys/class/net/ 2>&1 | tr '\n' ' ' | sed 's/^/  contents: /'
        echo
    else
        echo "  DOES NOT EXIST"
    fi
    echo

    echo "--- which entries look like a VPN ---"
    ls /sys/class/net/ 2>/dev/null | grep -E '^(tun|utun|ppp|wg)' | sed 's/^/  /' || echo "  none"
    echo

    echo "--- what the panel's own function returns ---"
    cd "$HOME/twitter_pixiv_tg_bot/control" || exit 1
    python - <<'PY'
import os
import sys
from pathlib import Path

sys.path.insert(0, ".")
sys.path.insert(0, "../bot")
sys.path.insert(0, "../bot/vendor")

try:
    import panel
    print(f"  vpn_interface() = {panel.vpn_interface()!r}")
    state = panel.proxy_state()
    print(f"  proxy_state()   = {state}")
except Exception as exc:
    print(f"  FAILED: {type(exc).__name__}: {exc}")

# And the raw path, to separate "the function is wrong" from "the directory is unreadable".
net = Path("/sys/class/net")
try:
    names = sorted(e.name for e in net.iterdir())
    print(f"  Path('/sys/class/net').iterdir() -> {len(names)} entries: {names[:8]}")
except Exception as exc:
    print(f"  iterdir() FAILED: {type(exc).__name__}: {exc}")
PY
    echo

    echo "--- does /proc/net/dev show the tunnel (a fallback that needs no sysfs) ---"
    grep -E "tun|ppp|wg" /proc/net/dev 2>/dev/null | sed 's/^/  /' || echo "  no tunnel in /proc/net/dev"
    echo

    echo "--- does ip report it (a subprocess fallback) ---"
    ip -o link show 2>/dev/null | grep -E "tun|ppp|wg" | sed 's/^/  /' || echo "  none"
} > "$OUT" 2>&1

echo "written to $OUT"

#!/data/data/com.termux/files/usr/bin/bash
# Which network-state sources can the Termux app actually read?
#
# /sys/class/net is blocked by SELinux in u:r:untrusted_app_27, which is where the panel runs and
# where RUN_COMMAND puts a script. So a detection built on it reports "no VPN" on a phone whose VPN
# is fine - the same false alarm as before, moved. This finds a source that is readable *from this
# domain*, because that is the only domain the panel ever runs in.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
OUT="$HOME/twitter_pixiv_tg_bot/data/network-sources.txt"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo "  context: $(cat /proc/self/attr/current 2>/dev/null)"
    echo

    probe() {
        label="$1"; path="$2"
        if [ -r "$path" ]; then
            lines=$(wc -l < "$path" 2>/dev/null || echo 0)
            echo "  READABLE   $label ($path), $lines lines"
        elif [ -e "$path" ]; then
            echo "  DENIED     $label ($path) exists but not readable"
        else
            echo "  ABSENT     $label ($path)"
        fi
    }

    echo "--- candidate files ---"
    probe "/proc/net/dev"    "/proc/net/dev"
    probe "/proc/net/route"  "/proc/net/route"
    probe "/proc/net/if_inet6" "/proc/net/if_inet6"
    probe "/sys/class/net"   "/sys/class/net"
    probe "/proc/net/tcp"    "/proc/net/tcp"
    echo

    echo "--- what /proc/net/dev contains ---"
    if [ -r /proc/net/dev ]; then
        cat /proc/net/dev 2>/dev/null | sed 's/^/  /'
    else
        echo "  not readable"
    fi
    echo

    echo "--- what /proc/net/route contains (tun lines are the signal) ---"
    if [ -r /proc/net/route ]; then
        head -20 /proc/net/route 2>/dev/null | sed 's/^/  /'
    else
        echo "  not readable"
    fi
    echo

    echo "--- commands that might report links ---"
    for tool in ip ifconfig getprop dumpsys; do
        if command -v "$tool" >/dev/null 2>&1; then
            echo "  $tool: $(command -v "$tool")"
        else
            echo "  $tool: not installed"
        fi
    done
    echo

    echo "--- what \`ip\` would say, if present ---"
    if command -v ip >/dev/null 2>&1; then
        ip -o link show 2>&1 | head -12 | sed 's/^/  /'
    else
        echo "  ip not available"
    fi
    echo

    echo "--- getprop as a last resort (Android exposes net.* properties) ---"
    if command -v getprop >/dev/null 2>&1; then
        getprop 2>/dev/null | grep -iE "net\.|vpn|tun" | head -15 | sed 's/^/  /'
    fi
    echo

    echo "--- python's own view of /proc/net/dev ---"
    python - <<'PY'
from pathlib import Path
for name in ("/proc/net/dev", "/proc/net/route", "/sys/class/net"):
    try:
        if Path(name).is_dir():
            entries = [e.name for e in Path(name).iterdir()]
            print(f"  {name}: dir with {len(entries)} entries = {entries[:8]}")
        else:
            text = Path(name).read_text(errors="replace")
            vpn = [line.split(":")[0].strip() for line in text.splitlines()
                   if any(k in line.lower() for k in ("tun", "ppp", "wg"))]
            print(f"  {name}: readable, {len(text.splitlines())} lines, vpn-ish = {vpn}")
    except Exception as exc:
        print(f"  {name}: {type(exc).__name__}: {exc}")
PY
} > "$OUT" 2>&1

echo "written to $OUT"

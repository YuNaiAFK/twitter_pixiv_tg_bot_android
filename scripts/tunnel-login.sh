#!/data/data/com.termux/files/usr/bin/bash
# Interactive Cloudflare login, which needs no token to be copied by hand.
#
#   bash scripts/tunnel-login.sh start     # prints and opens an authorisation URL
#   bash scripts/tunnel-login.sh status    # has the certificate appeared?
#   bash scripts/tunnel-login.sh cancel    # give up on a pending login
#
# **Why the proot container.** `cloudflared tunnel login` crashes in Termux with
#
#     SIGSYS: bad system call
#     syscall.faccessat2(...)
#     os/exec.findExecutable(...)
#     token.getBrowserCmd(...)  ->  token.OpenBrowser(...)
#
# faccessat2 is a syscall Android's seccomp filter rejects, and Go's exec.LookPath reaches it while
# hunting for a browser launcher. proot intercepts syscalls with ptrace, so inside the container the
# call never reaches the kernel and the crash does not happen - measured, not assumed.
#
# BROWSER=echo is the second half. It stops cloudflared from looking for a launcher at all and makes
# it print the URL instead, which is both what this needs and what avoids the crashing code path
# twice over.
#
# **Why not the token.** Copying the tunnel token out of the dashboard failed three times: the
# value arrived as a 36-character UUID twice and as the literal text <TOKEN> once, because the page
# shows the tunnel ID, the connector tokens and the install command close together. This route has
# nothing to copy - cloudflared writes the credential to disk itself.
set -u
export HOME="${HOME:-/data/data/com.termux/files/home}"
export PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_DIR="$PROJECT_DIR/data"
LOG_FILE="$RUN_DIR/tunnel-login.log"
URL_FILE="$RUN_DIR/tunnel-login-url.txt"
PID_FILE="$RUN_DIR/tunnel-login.pid"

CHROOT_NAME="${CHROOT_NAME:-botapi}"
PROOT_BASE="${PROOT_BASE:-$PREFIX/var/lib/proot-distro}"
ROOTFS="$PROOT_BASE/containers/$CHROOT_NAME/rootfs"
CONTAINER_CERT="/root/.cloudflared/cert.pem"

say() { printf '\033[1m%s\033[0m\n' "$1"; }
ok()  { printf '  \033[32m✓\033[0m %s\n' "$1"; }
no()  { printf '  \033[36m·\033[0m %s\n' "$1"; }
bad() { printf '  \033[31m✗\033[0m %s\n' "$1"; }

cert_exists() {
    [ -f "$ROOTFS$CONTAINER_CERT" ]
}

mkdir -p "$RUN_DIR"

case "${1:-start}" in
start)
    if cert_exists; then
        ok "already logged in"
        no "certificate: $ROOTFS$CONTAINER_CERT"
        no "delete it first to authorise a different account"
        exit 0
    fi
    [ -x "$ROOTFS/usr/local/bin/cloudflared" ] || {
        bad "cloudflared is not in the container - run scripts/login-route-probe.sh once"
        exit 1
    }

    say "Starting the Cloudflare login (in the container, so it does not crash)"
    : > "$LOG_FILE"
    rm -f "$URL_FILE"

    # setsid so it outlives this shell. It has to keep running: the callback goes to
    # login.cloudflareaccess.org rather than to localhost, and cloudflared collects the result by
    # polling that URL. Killing it early means the authorisation is never picked up.
    nohup setsid proot-distro login "$CHROOT_NAME" -- \
        /usr/bin/env BROWSER=echo /usr/local/bin/cloudflared tunnel login \
        >>"$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"

    for _ in $(seq 1 25); do
        URL=$(grep -oE 'https://dash\.cloudflare\.com/[^ ]+' "$LOG_FILE" 2>/dev/null | head -1)
        [ -n "$URL" ] && break
        sleep 1
    done

    if [ -z "${URL:-}" ]; then
        bad "no authorisation URL appeared within 25s"
        tail -n 15 "$LOG_FILE" | sed 's/^/    /'
        exit 1
    fi

    printf '%s\n' "$URL" > "$URL_FILE"
    ok "authorisation URL saved to $URL_FILE"
    printf '\n%s\n\n' "$URL"

    # Opened from here, in Termux's domain, because the container has no Android intent bridge -
    # it cannot start a browser, but this shell can.
    if command -v termux-open-url >/dev/null 2>&1; then
        termux-open-url "$URL" 2>/dev/null && ok "opened in the browser" \
            || no "could not open it; open the URL from $URL_FILE by hand"
    else
        no "termux-open-url not installed; open the URL by hand"
    fi

    printf '\n'
    no "Choose the domain, click Authorise, then run: $0 status"
    ;;

status)
    if cert_exists; then
        ok "logged in"
        no "certificate: $ROOTFS$CONTAINER_CERT"
        if [ -f "$PID_FILE" ]; then
            pid=$(cat "$PID_FILE" 2>/dev/null || true)
            if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
                kill "$pid" 2>/dev/null || true
                rm -f "$PID_FILE"
                no "the login process had finished its job; stopped it"
            fi
        fi
    else
        bad "not logged in yet"
        if [ -f "$URL_FILE" ]; then
            no "authorise at:"
            sed 's/^/    /' "$URL_FILE"
        fi
        if [ -f "$PID_FILE" ]; then
            pid=$(cat "$PID_FILE" 2>/dev/null || true)
            if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
                no "the login process is still waiting (pid $pid)"
            else
                no "the login process is no longer running - start it again"
            fi
        fi
        if [ -f "$LOG_FILE" ]; then
            no "last lines:"
            tail -n 6 "$LOG_FILE" | sed 's/^/    /'
        fi
    fi
    ;;

cancel)
    if [ -f "$PID_FILE" ]; then
        pid=$(cat "$PID_FILE" 2>/dev/null || true)
        [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
        rm -f "$PID_FILE"
    fi
    pkill -f 'cloudflared tunnel login' 2>/dev/null || true
    ok "cancelled"
    ;;

*)
    echo "usage: $0 start|status|cancel" >&2
    exit 2
    ;;
esac

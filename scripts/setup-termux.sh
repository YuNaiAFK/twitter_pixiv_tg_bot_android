#!/data/data/com.termux/files/usr/bin/bash
# Install the bot and its self-hosted Bot API server on Android.
#
# Target: a rooted OnePlus 8 Pro on Pixel Experience 13 (AOSP 13, kernel 4.19, aarch64).
# Nothing here is device-specific beyond that, and the probe explains what this device can do.
#
# Idempotent: every step checks first and says what it is skipping, so re-running after a
# failure resumes rather than starting over.
#
#   bash scripts/setup-termux.sh              # everything
#   bash scripts/setup-termux.sh --no-server  # bot only, 50 MB upload limit
#   bash scripts/setup-termux.sh --check      # report state, change nothing
#
# Two ways to reach the 2000 MB limit, and this script takes the second:
#
#   Docker        needs overlayfs + cgroups + namespaces, which an Android kernel often does
#                 not expose. The probe reports whether this one does.
#   chroot build  needs only root. Compiles telegram-bot-api inside a Debian chroot, which is
#                 the path that works on essentially every rooted device, so it is the
#                 default. Slower to install, identical once running.
#
# Either way the bot talks to http://127.0.0.1:8081, and TELEGRAM_LOCAL=1 is what raises the
# limit. Without a server the bot still works; it just falls back to the public 50 MB.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIX_TERMUX="${PREFIX:-/data/data/com.termux/files/usr}"
CHROOT_NAME="${CHROOT_NAME:-botapi}"
CHROOT_ROOT="${CHROOT_ROOT:-$PREFIX_TERMUX/var/lib/proot-distro/installed-rootfs/$CHROOT_NAME}"
API_PORT="${API_PORT:-8081}"
BUILD_SERVER=1
CHECK_ONLY=0

for arg in "$@"; do
    case "$arg" in
        --no-server) BUILD_SERVER=0 ;;
        --check)     CHECK_ONLY=1 ;;
        -h|--help)   sed -n '2,30p' "$0"; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

say()  { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
ok()   { printf '    \033[32m✓\033[0m %s\n' "$1"; }
skip() { printf '    \033[36m·\033[0m %s\n' "$1"; }
warn() { printf '    \033[33m!\033[0m %s\n' "$1"; }
die()  { printf '    \033[31m✗ %s\033[0m\n' "$1" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

run() {
    # Print the command, then run it - an installer that fails silently is worse than one
    # that is noisy.
    printf '    $ %s\n' "$*"
    "$@"
}

is_root() { [ "$(id -u)" = "0" ]; }

# -------------------- 1. Termux packages --------------------

say "Termux packages"
if [ "$CHECK_ONLY" = "1" ]; then
    for p in python clang libjpeg-turbo libpng freetype proot-distro; do
        if dpkg -s "$p" >/dev/null 2>&1; then ok "$p installed"; else skip "$p missing"; fi
    done
else
    run pkg update -y || warn "pkg update reported a problem; continuing"
    # The image libraries are Pillow's build dependencies: without them pip tries to compile
    # from source and fails on the missing headers rather than installing a wheel.
    run pkg install -y python clang make libjpeg-turbo libpng freetype proot-distro git
    ok "packages installed"
fi

# -------------------- 2. Python packages --------------------

say "Python packages"
if [ "$CHECK_ONLY" = "1" ]; then
    python - <<'PY' || true
import importlib
for name in ("telegram", "httpx", "PIL", "gallery_dl", "dotenv"):
    try:
        mod = importlib.import_module(name)
        print(f"    \033[32m✓\033[0m {name} {getattr(mod, '__version__', '')}")
    except Exception as exc:
        print(f"    \033[36m·\033[0m {name} missing ({exc.__class__.__name__})")
PY
else
    run python -m pip install --upgrade pip
    run python -m pip install python-telegram-bot httpx pillow gallery-dl python-dotenv
    ok "installed"
fi

# -------------------- 3. project layout --------------------

say "Project"
if [ -f "$PROJECT_DIR/.env" ]; then
    skip ".env already exists (never overwritten - it holds your tokens)"
else
    if [ -f "$PROJECT_DIR/.env.example" ]; then
        cp "$PROJECT_DIR/.env.example" "$PROJECT_DIR/.env"
        warn ".env created from the example - fill in BOT_TOKEN and ADMIN_USER_IDS"
    else
        warn "no .env.example; create .env from the README by hand"
    fi
fi
if [ ! -d "$PROJECT_DIR/data" ]; then
    if [ "$CHECK_ONLY" = "0" ]; then
        mkdir -p "$PROJECT_DIR/data"
        ok "created data/"
    fi
else
    skip "data/ exists"
fi
if [ -d "$PROJECT_DIR/cookies" ]; then
    ok "cookies/ present"
else
    warn "no cookies/ directory - Twitter and e-hentai need cookie files there"
fi

# -------------------- 4. checks that do not need the server --------------------

say "Bot self-check"
if [ "$CHECK_ONLY" = "0" ]; then
    # --check never contacts Telegram, so this is safe to run before .env is filled in, and
    # it reports the missing pieces in the bot's own words.
    if python "$PROJECT_DIR/bot/bot.py" --check 2>&1 | sed 's/^/    /'; then
        ok "bot code loads"
    else
        warn "the self-check reported a problem - read the lines above"
    fi
else
    skip "skipped in --check mode"
fi

# -------------------- 5. the self-hosted server --------------------

if [ "$BUILD_SERVER" = "0" ]; then
    say "Self-hosted server: SKIPPED (--no-server)"
    warn "the upload limit stays at 50 MB; MAX_UPLOAD_MB=45 already fits inside it"
else
    say "Self-hosted Bot API server"
    warn "this compiles TDLib and takes roughly 20-60 minutes on a phone"
    warn "run it with a charger attached, or leave it overnight"

    if [ "$CHECK_ONLY" = "1" ]; then
        if [ -x "$CHROOT_ROOT/usr/local/bin/telegram-bot-api" ]; then
            ok "server binary present"
        else
            skip "server not built yet"
        fi
        if curl -fsS "http://127.0.0.1:$API_PORT/" >/dev/null 2>&1; then
            ok "server responding on :$API_PORT"
        else
            skip "server not running"
        fi
    else
        is_root || die "building the server needs root (a chroot is required). Re-run with su."
        have proot-distro || die "proot-distro is missing; pkg install proot-distro"

        if [ -d "$CHROOT_ROOT" ]; then
            skip "chroot '$CHROOT_NAME' already installed"
        else
            run proot-distro install --name "$CHROOT_NAME" debian
            ok "Debian chroot installed"
        fi

        # **The chroot has its own apt and its own git, and neither inherits Termux's proxy.**
        #
        # Termux's own `apt.conf.d/95proxy` is inside $PREFIX and means nothing to a Debian
        # rootfs, while the build's first two steps are `apt-get update` and a `git clone` from
        # github.com. Without this the build fails at once in mainland China - the same failure
        # that made `pkg` report "does not have a Release file" earlier, and for the same reason:
        # a proxy apt cannot use.
        #
        # Two properties matter:
        #
        #   the HTTP form    apt rejects a SOCKS proxy outright ("Unsupported proxy configured"),
        #                    and git is happiest with the same shape
        #   `--system` git   so the credentials are not attributed to a user that does not exist
        #                    in the chroot
        #
        # The chroot shares Termux's /tmp via `--shared-tmp`, so the value is handed over in a
        # file rather than by quoting it into three nested shells.
        PROXY_FOR_CHROOT=$(cat "$HOME/.proxy-url" 2>/dev/null || true)
        case "$PROXY_FOR_CHROOT" in
            http://*|https://*) ;;
            "") warn "no ~/.proxy-url; the chroot will try a direct connection" ;;
            *)
                # A SOCKS URL would be worse than none: apt refuses it AND reports the failure
                # as a broken repository, which is the misleading message that cost hours.
                warn "~/.proxy-url is not an http:// URL ($PROXY_FOR_CHROOT)"
                warn "apt cannot use SOCKS - clearing it so the failure is honest"
                PROXY_FOR_CHROOT=""
                ;;
        esac
        if [ -n "$PROXY_FOR_CHROOT" ]; then
            printf '%s\n' "$PROXY_FOR_CHROOT" > "$HOME/.proxy-for-chroot"
            ok "passing the proxy to the chroot as $PROXY_FOR_CHROOT"
        else
            : > "$HOME/.proxy-for-chroot"
        fi
        # One script, run inside the chroot. Written to a file rather than a long -c string
        # so a failure points at a readable line.
        cat > "$PROJECT_DIR/scripts/build-server-in-chroot.sh" <<'INNER'
#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# Pick up the proxy that setup-termux.sh left in the shared /tmp, and configure apt to use it.
# apt ignores the *_proxy environment variables for its own transport, so the config file is
# not optional - the environment alone would still fail.
if [ -r /tmp/.proxy-for-chroot ]; then
    PROXY_URL=$(cat /tmp/.proxy-for-chroot)
fi
if [ -n "${PROXY_URL:-}" ]; then
    echo "==> proxy: $PROXY_URL"
    export http_proxy="$PROXY_URL" https_proxy="$PROXY_URL" all_proxy="$PROXY_URL"
    mkdir -p /etc/apt/apt.conf.d
    {
        printf 'Acquire::http::Proxy "%s";\n' "$PROXY_URL"
        printf 'Acquire::https::Proxy "%s";\n' "$PROXY_URL"
    } > /etc/apt/apt.conf.d/95proxy
    git config --system http.proxy "$PROXY_URL" || true
    git config --system https.proxy "$PROXY_URL" || true
else
    echo "==> no proxy configured; using a direct connection"
fi

echo "==> apt packages"
apt-get update
apt-get install -y --no-install-recommends \
    build-essential cmake gperf git zlib1g-dev libssl-dev \
    libreadline-dev libsqlite3-dev ca-certificates
echo "==> telegram-bot-api (TDLib is fetched and built by its own CMake)"
rm -rf /opt/telegram-bot-api
git clone --depth 1 https://github.com/tdlib/telegram-bot-api.git /opt/telegram-bot-api
cd /opt/telegram-bot-api
cmake -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local
# -j2 deliberately: a phone has 8 cores but thermal-throttles, and a killed build wastes far
# more time than a slower one.
cmake --build build --target install -j2
echo "==> installed:"
ls -l /usr/local/bin/telegram-bot-api
INNER
        chmod +x "$PROJECT_DIR/scripts/build-server-in-chroot.sh"
        # The proxy is handed over through Termux's own tmp directory, because `--shared-tmp`
        # is what binds it to /tmp inside the chroot. Writing it to $HOME instead would leave
        # the chroot without it: /tmp and $HOME are different directories, and only /tmp is
        # shared.
        mkdir -p "$PREFIX/tmp"
        cp "$HOME/.proxy-for-chroot" "$PREFIX/tmp/.proxy-for-chroot" 2>/dev/null || true
        run proot-distro login "$CHROOT_NAME" --shared-tmp -- bash "/$PROJECT_DIR/scripts/build-server-in-chroot.sh" \
            || die "the build failed - the tail of the output above says which step"

        if [ -x "$CHROOT_ROOT/usr/local/bin/telegram-bot-api" ]; then
            ok "server built"
        else
            # proot-distro keeps the rootfs in a known place; if the binary is somewhere else
            # the path is worth printing rather than guessing.
            found=$(find "$CHROOT_ROOT" -name telegram-bot-api -type f 2>/dev/null | head -1 || true)
            [ -n "$found" ] && ok "server built at $found" || die "the build reported success but no binary was found"
        fi
    fi
fi

# -------------------- 6. next steps --------------------

say "Next steps"
if [ "$BUILD_SERVER" = "1" ] && [ "$CHECK_ONLY" = "0" ]; then
    printf '    1. Fill in %s/.env\n' "$PROJECT_DIR"
    printf '         BOT_TOKEN=...\n'
    printf '         ADMIN_USER_IDS=<your numeric id from /id>\n'
    printf '         TELEGRAM_API_ID / TELEGRAM_API_HASH   (from my.telegram.org)\n'
    printf '         TELEGRAM_API_BASE=http://127.0.0.1:%s\n' "$API_PORT"
    printf '         TELEGRAM_LOCAL=1\n'
    printf '    2. Put cookie files in cookies/  (twitter.txt, ehentai.txt - Netscape format)\n'
    printf '    3. Start the server:  bash scripts/run-server.sh start\n'
    printf '    4. Start the bot:     bash scripts/run-bot.sh\n'
else
    printf '    1. Fill in %s/.env  (BOT_TOKEN and ADMIN_USER_IDS at minimum)\n' "$PROJECT_DIR"
    printf '    2. Put cookie files in cookies/\n'
    printf '    3. Start the bot:     bash scripts/run-bot.sh\n'
    printf '\n'
    printf '    The upload limit will be 50 MB. To raise it, run this script without\n'
    printf '    --no-server.\n'
fi
printf '\n'
printf '    Read the probe first if anything failed:  bash scripts/probe-device.sh\n'

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
PROOT_BASE="${PROOT_BASE:-$PREFIX_TERMUX/var/lib/proot-distro}"

# **proot-distro 5.x moved the rootfs, and checking only the old path makes the script try to
# reinstall a container that already exists:**
#
#     Error: container 'botapi' already exists. Specify a different name with '--name NAME'.
#
#   5.x   $PROOT_BASE/containers/<name>/rootfs
#   4.x   $PROOT_BASE/installed-rootfs/<name>
#
# The measured layout on this device is the 5.x one: containers/botapi/rootfs, 658 MB, with
# manifest.json beside it. Both are checked so the script works either way, and PROOT_BASE can be
# overridden if a future version moves it again.
if [ -d "$PROOT_BASE/containers/$CHROOT_NAME/rootfs" ]; then
    CHROOT_ROOT="$PROOT_BASE/containers/$CHROOT_NAME/rootfs"
else
    CHROOT_ROOT="${CHROOT_ROOT:-$PROOT_BASE/installed-rootfs/$CHROOT_NAME}"
fi
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
    # **`pip install --upgrade pip` is deliberately NOT run.** Termux refuses it outright:
    #
    #     ERROR: Installing pip is forbidden, this will break the python-pip package (termux).
    #
    # Termux manages pip through `pkg`, so upgrading it with pip desynchronises the two. Under
    # `set -euo pipefail` that refusal aborted the entire script - which is why the server build
    # never started, and why the message about a forbidden pip upgrade was the last thing seen.
    # Upgrading pip is not needed to install what follows; `pkg upgrade` is the right way to
    # move pip on Termux.
    #
    # Each package is checked by importing it, so a re-run only fetches what is genuinely
    # absent, and a single failure does not stop the others.
    for pkg in telegram httpx PIL gallery_dl dotenv; do
        if python -c "import $pkg" >/dev/null 2>&1; then
            skip "$pkg already installed"
            continue
        fi
        case "$pkg" in
            telegram)   pipname="python-telegram-bot" ;;
            PIL)        pipname="pillow" ;;
            gallery_dl) pipname="gallery-dl" ;;
            dotenv)     pipname="python-dotenv" ;;
            *)          pipname="$pkg" ;;
        esac
        run python -m pip install "$pipname"
    done
    ok "python packages present"
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
        # **No root requirement.** This used to `die` unless running as uid 0, which blocked the
        # build with "building the server needs root (a chroot is required). Re-run with su."
        # That was wrong for this approach.
        #
        # proot implements chroot and mount with ptrace inside a userspace process; it needs no
        # privileges, which is the whole reason it works on an unrooted Android. What needs root
        # is a real chroot(2)/mount(2) build - a different technique from the one used here.
        #
        # Measured as a normal user on this device: `proot-distro list` answers normally, and
        # `$PREFIX/var/lib` and `$PREFIX/tmp` - where it keeps containers and downloads - are
        # both writable by the Termux user.
        #
        # Root is still worth mentioning, because `su` changes the SELinux domain to
        # `u:r:magisk:s0`, which cannot read Termux's own directories. Running the build as root
        # would break it, not fix it.
        if is_root; then
            warn "running as root: Termux's directories may be unreadable from this domain"
            warn "run this as the normal Termux user instead"
        fi
        have proot-distro || die "proot-distro is missing; pkg install proot-distro"

        # Ask proot-distro itself whether the container exists, rather than inferring it from a
        # path. A path test is what broke here: 5.x keeps the rootfs at
        # containers/<name>/rootfs while the script looked at installed-rootfs/<name>, so it
        # decided to install again and was told "container 'botapi' already exists".
        #
        # `list` is the authoritative answer and is version-independent.
        if proot-distro list 2>/dev/null | grep -qE "^[[:space:]]*\*?[[:space:]]*$CHROOT_NAME[[:space:]]*$"; then
            skip "container '$CHROOT_NAME' already installed"
        elif [ -d "$CHROOT_ROOT" ]; then
            skip "chroot '$CHROOT_NAME' already present at $CHROOT_ROOT"
        else
            # The name is an option, not a positional argument in 5.x:
            #   proot-distro install [OPTIONS] (IMAGE:TAG or URL or FILE)
            # `--name=...` is used so the value cannot be mistaken for the image reference.
            run proot-distro install --name="$CHROOT_NAME" debian:stable
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

# **Scrub the Termux environment before configuring.**
#
# This is the bug that made the first build die at 3%, and its symptom points nowhere near its
# cause. TDLib's CMake asks pkg-config where OpenSSL is. Termux's PKG_CONFIG_PATH was inherited
# into the chroot, so pkg-config answered with **Termux's** OpenSSL, and CMake baked it in:
#
#     OPENSSL_INCLUDE_DIR:PATH        = /data/data/com.termux/files/usr/include
#     OPENSSL_CRYPTO_LIBRARY:FILEPATH = /data/data/com.termux/files/usr/lib/libcrypto.so
#     _OPENSSL_CFLAGS:INTERNAL        = -I/data/data/com.termux/files/usr/include
#
# which produced `-isystem /data/data/com.termux/files/usr/include` on every compile line. Using
# Debian's gcc with Termux's Android/bionic headers cannot work, so sqlite3.c failed with errors
# from android/api-level.h, sys/cdefs.h and string.h - files that have nothing to do with sqlite.
#
# Both halves have to go: the variables that carry the paths in, and any build directory that
# already recorded them. CMake caches the detection results, so a stale cache reproduces the
# failure even after the environment is fixed.
for v in PKG_CONFIG_PATH PKG_CONFIG_LIBDIR PKG_CONFIG_SYSROOT_DIR \
         CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH \
         LIBRARY_PATH LD_LIBRARY_PATH LD_PRELOAD \
         CMAKE_PREFIX_PATH CMAKE_INCLUDE_PATH CMAKE_LIBRARY_PATH \
         CFLAGS CXXFLAGS LDFLAGS CPPFLAGS; do
    unset "$v" 2>/dev/null || true
done
# An empty PATH entry or one pointing outside the chroot would let the host's tools be used.
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
# Be explicit about the compiler rather than letting CMake search: /usr/bin/cc exists in Termux
# too, so an unqualified search could resolve outside the chroot.
export CC=/usr/bin/gcc
export CXX=/usr/bin/g++
echo "    scrubbed inherited paths (PKG_CONFIG_PATH, CPATH, LD_LIBRARY_PATH, ...)"

# Remove any build tree that recorded the old detection. Cheap insurance: a stale CMakeCache
# with Termux paths in it fails identically to the original bug.
rm -rf build

# **`td` is a git submodule, and without it CMake fails in a way that names the wrong thing.**
#
# The top-level CMakeLists.txt does:
#
#     add_subdirectory(td EXCLUDE_FROM_ALL)                        # line 5
#     set(CMAKE_MODULE_PATH ".../td/CMake" "${CMAKE_MODULE_PATH}")  # line 10
#     include(PreventInSourceBuild)                                # line 21
#     prevent_in_source_build()                                    # line 22
#
# A plain `git clone` leaves td/ empty, so CMAKE_MODULE_PATH points at nothing, `include()`
# fails without stopping the configure, and the error surfaces one line later as:
#
#     CMake Error at CMakeLists.txt:22 (prevent_in_source_build):
#       Unknown CMake command "prevent_in_source_build".
#
# That reads like a broken upstream CMakeLists or a missing CMake package, neither of which is
# true - the file exists, in the submodule. `--recursive` is not implied by `--depth 1`.
echo "==> submodules (td provides PreventInSourceBuild.cmake and all of TDLib)"
git submodule update --init --recursive

if [ ! -f td/CMake/PreventInSourceBuild.cmake ]; then
    echo "ERROR: td/CMake/PreventInSourceBuild.cmake is still missing after the submodule update."
    echo "       Check the network and re-run; the build cannot configure without it."
    exit 1
fi
echo "    submodules present"

# Report what pkg-config now says, so a future recurrence is visible immediately rather than
# showing up as unrelated compiler errors twenty minutes later.
if command -v pkg-config >/dev/null 2>&1; then
    echo "    pkg-config resolves openssl to:"
    pkg-config --variable=includedir openssl 2>/dev/null | sed 's/^/      include: /' || echo "      (openssl.pc not found)"
    case "$(pkg-config --variable=includedir openssl 2>/dev/null || true)" in
        /data/data/com.termux/*)
            echo "ERROR: pkg-config is still reporting a Termux path. The build would fail."
            exit 1 ;;
    esac
fi

# CMAKE_BUILD_TYPE=Release and the install prefix are set on the configure line; the build
# target is built separately so a failure names the step.
cmake -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local \
      -DCMAKE_C_COMPILER=/usr/bin/gcc -DCMAKE_CXX_COMPILER=/usr/bin/g++

# Guard against the exact regression that caused the original failure: if any compile line still
# names a Termux include directory, stop before spending half an hour on it.
if grep -rq 'isystem /data/data/com.termux' build 2>/dev/null; then
    echo "ERROR: the generated build files still contain a Termux include path:"
    grep -rh -m2 'isystem /data/data/com.termux[^ ]*' build 2>/dev/null | head -3 | sed 's/^/      /'
    echo "       Refusing to build; the result could not compile."
    exit 1
fi
echo "    no Termux paths in the generated build files"

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

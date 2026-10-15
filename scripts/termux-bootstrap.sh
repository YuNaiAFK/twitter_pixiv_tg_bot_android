#!/data/data/com.termux/files/usr/bin/bash
# Termux bootstrap — run this from inside the Termux app.
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/YuNaiAFK/twitter_pixiv_tg_bot_android/main/scripts/termux-bootstrap.sh)
#
# Why it must run in the app rather than over adb: Android grants network access per process,
# keyed on the SELinux domain. Termux's own process runs as
# `u:r:untrusted_app_27:s0:c209,...` and has it; a process started with `su 10209` from adb
# lands in `u:r:magisk:s0` and does not - measured, every connection from it fails with
# `socket: Permission denied`, while uid 0 succeeds.
#
# Three failures shaped this script, all found on this device and all fixed by measurement:
#
#   1. `pkg upgrade`    hung the whole install. dpkg asks about configuration-file conflicts
#                       even under DEBIAN_FRONTEND=noninteractive, and with no terminal it
#                       waits forever. It is not needed: `pkg install` resolves dependencies.
#   2. `dpkg --configure -a` with output thrown away looked like a hang for the same reason:
#                       the OpenSSL conffile prompt was waiting on a keyboard that never
#                       answered, invisibly. Fixed by `</dev/null` plus --force-confold.
#   3. mirror switching  was the wrong default for a phone that already has a VPN. The proxy is
#                       tried first and mirror changes only happen without one.
#
# Every command that can prompt does so with stdin from /dev/null, so a question can never
# block: it reads EOF and takes its default.

set -u

REPO_URL="${REPO_URL:-https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android.git}"
CLONE_DIR="${CLONE_DIR:-$HOME/twitter_pixiv_tg_bot}"
WITH_SERVER=1
NO_MIRROR=0

for arg in "$@"; do
    case "$arg" in
        --no-server) WITH_SERVER=0 ;;
        --no-mirror) NO_MIRROR=1 ;;
        --repo=*)    REPO_URL="${arg#--repo=}" ;;
    esac
done

say()  { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
ok()   { printf '    \033[32m✓\033[0m %s\n' "$1"; }
info() { printf '    \033[36m·\033[0m %s\n' "$1"; }
warn() { printf '    \033[33m!\033[0m %s\n' "$1"; }
die()  { printf '    \033[31m✗ %s\033[0m\n' "$1" >&2; exit 1; }

# Never let a prompt block: EOF makes dpkg take its default instead of waiting.
export DEBIAN_FRONTEND=noninteractive
DPKG_OPTS="--force-confold --force-confdef"
APT_OPTS="-o Dpkg::Options::=--force-confold -o Dpkg::Options::=--force-confdef -o Dpkg::Use-Pty=0"

# -------------------- proxy first --------------------

say "Proxy"
# A working VPN is strictly better than any mirror: it reaches GitHub, pip and the TDLib source
# as well as the package index. Measured on this phone: v2rayNG on 10808 answers 200 as both
# SOCKS5 and HTTP.
PROXY_URL=""
OPEN_PORTS=""
for port in 10808 10809 7890 7891 1080 8118 8889; do
    if (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
        exec 3<&- 3>&- 2>/dev/null
        OPEN_PORTS="$OPEN_PORTS $port"
    fi
done

if [ -n "$OPEN_PORTS" ]; then
    info "listening locally:$OPEN_PORTS"
    # **Both forms are recorded, and pip needs the HTTP one.**
    #
    # pip cannot use a SOCKS proxy without PySocks, and installing PySocks needs pip - so
    # `http_proxy=socks5://...` makes every pip invocation fail with "Missing dependencies for
    # SOCKS support". Measured on this phone: v2rayNG's port answers BOTH protocols, so the
    # same port works as `http://` for pip while apt, curl and git keep the SOCKS form.
    for port in $OPEN_PORTS; do
        for scheme in socks5 http; do
            code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
                   -x "$scheme://127.0.0.1:$port" https://github.com/ 2>/dev/null || echo "000")
            case "$code" in
                200|301|302)
                    if [ "$scheme" = "socks5" ]; then
                        SOCKS_URL="socks5://127.0.0.1:$port"
                    else
                        HTTP_URL="http://127.0.0.1:$port"
                    fi
                    ok "$scheme://127.0.0.1:$port works (github.com -> HTTP $code)"
                    ;;
            esac
        done
        [ -n "$SOCKS_URL" ] && [ -n "$HTTP_URL" ] && break
    done
    PROXY_URL="${SOCKS_URL:-$HTTP_URL}"
    [ -n "$HTTP_URL" ] || warn "no HTTP form answered; pip will fall back to a direct connection"
else
    info "no local proxy port is listening"
fi

if [ -z "$PROXY_URL" ]; then
    if curl -fsS --max-time 12 -o /dev/null https://github.com/ 2>/dev/null; then
        ok "no proxy needed - github.com is directly reachable"
    else
        warn "no proxy and no direct route; switching the VPN on and re-running is the fix"
    fi
fi

if [ -n "$PROXY_URL" ]; then
    # apt, curl and git all speak SOCKS, so they get the best form available.
    export http_proxy="$PROXY_URL" https_proxy="$PROXY_URL" all_proxy="$PROXY_URL"
    export HTTP_PROXY="$PROXY_URL" HTTPS_PROXY="$PROXY_URL" ALL_PROXY="$PROXY_URL"
    # **The HTTP form is what gets written to disk and to the config files.**
    #
    # apt rejects a SOCKS proxy outright -
    #
    #     Unsupported proxy configured: socks5://127.0.0.1:10808
    #     E: The repository '...' does not have a Release file.
    #
    # - and worse, the message names the REPOSITORY, so it reads as a broken mirror. Measured
    # on this phone: every Termux mirror served its Release file fine from the PC, while apt
    # failed on all of them because the proxy in apt.conf.d could not be used. pip has the same
    # limitation for a different reason (it needs PySocks). Both work with `http://`, which
    # v2rayNG also answers on this port.
    SAVED_URL="${HTTP_URL:-$PROXY_URL}"
    printf '%s\n' "$SAVED_URL" > "$HOME/.proxy-url"
    [ -n "$SOCKS_URL" ] && printf '%s\n' "$SOCKS_URL" > "$HOME/.proxy-url-socks"
    # apt ignores the *_proxy variables for its own transport; only the config file works, and
    # it must be a form apt understands.
    mkdir -p "$PREFIX/etc/apt/apt.conf.d"
    {
        printf 'Acquire::http::Proxy "%s";\n' "$SAVED_URL"
        printf 'Acquire::https::Proxy "%s";\n' "$SAVED_URL"
    } > "$PREFIX/etc/apt/apt.conf.d/95proxy"
    # git needs its own setting, and only for github.com: a global http.proxy would break the
    # user's other repositories.
    git config --global http.https://github.com/.proxy "$SAVED_URL" 2>/dev/null || true
    ok "saved for later sessions, and given to apt and git as $SAVED_URL"
fi

# -------------------- mirror (only without a proxy) --------------------

say "Package mirror"
if [ -n "$PROXY_URL" ] || [ "$NO_MIRROR" = "1" ]; then
    if [ -n "$PROXY_URL" ]; then
        ok "left alone - the proxy reaches the default mirror"
    else
        ok "left alone (--no-mirror)"
    fi
else
    # The default is mirror.mephi.ru, in Russia, which does not answer from mainland China.
    CHOSEN=""
    for m in \
        "https://mirrors.tuna.tsinghua.edu.cn/termux/apt/termux-main" \
        "https://mirrors.ustc.edu.cn/termux/apt/termux-main" \
        "https://mirror.nju.edu.cn/termux/apt/termux-main" \
        "https://packages.termux.dev/apt/termux-main" ; do
        if curl -fsS --max-time 15 -o /dev/null "$m/dists/stable/Release" 2>/dev/null; then
            CHOSEN="$m"; ok "using $m"; break
        fi
    done
    if [ -z "$CHOSEN" ]; then
        warn "no mirror answered - leaving the configuration alone"
    else
        mkdir -p "$PREFIX/etc/apt/sources.list.d"
        printf 'deb %s stable main\n' "$CHOSEN" > "$PREFIX/etc/apt/sources.list.d/termux-main.list"
        if [ -f "$PREFIX/etc/apt/sources.list" ]; then
            grep -v '^deb ' "$PREFIX/etc/apt/sources.list" > "$PREFIX/etc/apt/sources.list.tmp" 2>/dev/null || true
            mv "$PREFIX/etc/apt/sources.list.tmp" "$PREFIX/etc/apt/sources.list" 2>/dev/null || true
        fi
        ok "mirror configured"
    fi
fi

# -------------------- packages --------------------

say "Packages"

# Clear locks left by an interrupted run; a held lock makes the next apt refuse to start.
for f in "$PREFIX/var/lib/dpkg/lock" "$PREFIX/var/lib/dpkg/lock-frontend" \
         "$PREFIX/var/lib/apt/lists/lock" "$PREFIX/var/cache/apt/archives/lock"; do
    [ -e "$f" ] && rm -f "$f" 2>/dev/null && info "cleared $(basename "$f")"
done

# Finish anything half-configured. **stdin from /dev/null is the fix**, not the flags alone:
# without it dpkg stops at the OpenSSL conffile prompt and waits for a keyboard that is not
# there. Measured on this device: exit 0 in seconds with it, an indefinite hang without.
info "finishing any half-configured packages"
if ! dpkg $DPKG_OPTS --configure -a </dev/null 2>&1 | tail -n 5; then
    warn "dpkg --configure reported a problem; continuing anyway"
fi

info "updating the package index"
if ! apt-get update $APT_OPTS </dev/null 2>&1 | tail -n 4; then
    warn "apt-get update failed; the install below may not resolve"
fi

info "installing python, git and the Pillow build dependencies"
# shellcheck disable=SC2086
if ! apt-get install -y $APT_OPTS </dev/null \
        python git clang make libjpeg-turbo libpng freetype openssl libffi proot-distro \
        2>&1 | tail -n 20; then
    warn "apt-get install reported a problem"
fi

if ! command -v python >/dev/null; then
    die "python is still missing. Check the output above for the reason."
fi
ok "python $(python --version 2>&1 | awk '{print $2}')"

say "Python packages"
# **pip gets the HTTP form of the proxy, not the SOCKS one.**
#
# pip refuses a `socks5://` proxy unless PySocks is installed, and installing PySocks needs pip
# - so the SOCKS form makes every pip run fail with "Missing dependencies for SOCKS support",
# which is what happened on this phone. The HTTP form needs nothing extra. If no HTTP proxy was
# found, the variables are cleared so pip tries a direct connection rather than failing on a
# protocol it cannot speak.
if [ -n "${HTTP_URL:-}" ]; then
    export http_proxy="$HTTP_URL" https_proxy="$HTTP_URL" all_proxy="$HTTP_URL"
    export HTTP_PROXY="$HTTP_URL" HTTPS_PROXY="$HTTP_URL" ALL_PROXY="$HTTP_URL"
    info "pip will use $HTTP_URL (HTTP form - pip cannot speak SOCKS)"
else
    unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY
    info "no HTTP proxy; pip will connect directly"
fi

python -m pip install --upgrade pip </dev/null 2>&1 | tail -n 2
if ! python -m pip install python-telegram-bot httpx pillow gallery-dl python-dotenv </dev/null 2>&1 | tail -n 20; then
    warn "pip install reported a problem"
fi

# **Verify by importing, not by checking an exit code.** The previous version piped pip through
# `tail` and tested the pipeline's status, which is tail's - always 0 - so a total failure was
# reported as success and only surfaced when the bot would not start.
if python - <<'PY'
import importlib, sys
missing = []
for name in ("telegram", "httpx", "PIL", "gallery_dl", "dotenv"):
    try:
        importlib.import_module(name)
    except Exception:
        missing.append(name)
if missing:
    print("MISSING: " + ", ".join(missing))
    sys.exit(1)
print("all imports OK")
PY
then
    ok "imports verified"
else
    die "Python packages are still missing - see the output above"
fi

# -------------------- project --------------------

say "Project"
if [ -d "$CLONE_DIR/.git" ]; then
    info "already cloned; updating"
    git -C "$CLONE_DIR" pull --ff-only </dev/null 2>&1 | tail -n 3
else
    git clone --depth 1 "$REPO_URL" "$CLONE_DIR" </dev/null || die "git clone failed"
fi
cd "$CLONE_DIR" || die "cannot enter $CLONE_DIR"
ok "at $CLONE_DIR"

if [ -f .env ]; then
    info ".env exists - not touched"
else
    [ -f .env.example ] && cp .env.example .env && warn ".env created - fill in BOT_TOKEN and ADMIN_USER_IDS"
fi
mkdir -p data cookies
ok "data/ and cookies/ ready"

# -------------------- the server --------------------

if [ "$WITH_SERVER" = "0" ]; then
    say "Self-hosted server: skipped (--no-server)"
    warn "upload limit stays at 50 MB; MAX_UPLOAD_MB=45 already fits inside it"
else
    say "Self-hosted Bot API server"
    warn "this compiles TDLib: 20-60 minutes on a phone, and it is CPU-bound"
    warn "keep it on a charger and leave it alone"
    printf '\n    Continue now? [y/N] '
    read -r answer
    case "$answer" in
        y|Y) bash scripts/setup-termux.sh ;;
        *)   warn "skipped - run 'bash scripts/setup-termux.sh' later to build it" ;;
    esac
fi

# -------------------- next --------------------

say "Done"
cat <<'NEXT'
    Edit the configuration:

        nano ~/twitter_pixiv_tg_bot/.env

      BOT_TOKEN        from @BotFather
      ADMIN_USER_IDS   your id, from /id in a private chat with the bot
      TELEGRAM_API_ID  from my.telegram.org
      TELEGRAM_API_HASH
      TELEGRAM_API_BASE=http://127.0.0.1:8081
      TELEGRAM_LOCAL=1

    Put the cookie files in ~/twitter_pixiv_tg_bot/cookies/
    (twitter.txt, ehentai.txt - Netscape format)

    Then run:

        bash ~/twitter_pixiv_tg_bot/scripts/run-bot.sh

    To keep the proxy in future sessions, add to ~/.bashrc:

        export http_proxy=$(cat ~/.proxy-url)
        export https_proxy=$http_proxy
        export all_proxy=$http_proxy

    ~/.proxy-url holds the HTTP form, because apt and pip cannot use SOCKS. The SOCKS form,
    if the proxy offered one, is in ~/.proxy-url-socks for tools that prefer it.
NEXT

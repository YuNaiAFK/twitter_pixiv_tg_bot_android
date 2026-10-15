#!/data/data/com.termux/files/usr/bin/bash
# Termux bootstrap — run this from inside the Termux app.
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/YuNaiAFK/twitter_pixiv_tg_bot_android/main/scripts/termux-bootstrap.sh)
#
# Why it must run in the app rather than over adb: Android grants network access per process,
# keyed on the SELinux domain. Termux's own process runs as
# `u:r:untrusted_app_27:s0:c209,...` and has it; a process started with `su 10209` from adb
# lands in `u:r:magisk:s0` and does not - measured, every connection from it fails with
# `socket: Permission denied`, including a bare `ping 8.8.8.8`, while uid 0 succeeds.
#
# **The phone's own proxy is used when one is running**, because a working VPN is strictly
# better than any mirror: it makes GitHub, pip and the TDLib source all reachable, not just the
# package index. Mirror switching is a fallback for when there is no proxy, not the default.

set -u

REPO_URL="${REPO_URL:-https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android.git}"
CLONE_DIR="${CLONE_DIR:-$HOME/twitter_pixiv_tg_bot}"
WITH_SERVER=1

for arg in "$@"; do
    case "$arg" in
        --no-server) WITH_SERVER=0 ;;
        --no-mirror) NO_MIRROR=1 ;;
        --repo=*)    REPO_URL="${arg#--repo=}" ;;
    esac
done
NO_MIRROR="${NO_MIRROR:-0}"

say()  { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
ok()   { printf '    \033[32m✓\033[0m %s\n' "$1"; }
info() { printf '    \033[36m·\033[0m %s\n' "$1"; }
warn() { printf '    \033[33m!\033[0m %s\n' "$1"; }
die()  { printf '    \033[31m✗ %s\033[0m\n' "$1" >&2; exit 1; }

# -------------------- proxy first --------------------

say "Proxy"
# v2rayNG defaults to SOCKS5 on 10808 and HTTP on 10809; other clients use 7890/7891. Both
# protocols are tried per port, because the wrong guess looks exactly like a dead proxy.
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
    for port in $OPEN_PORTS; do
        for scheme in socks5 http; do
            code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
                   -x "$scheme://127.0.0.1:$port" https://github.com/ 2>/dev/null || echo "000")
            case "$code" in
                200|301|302)
                    PROXY_URL="$scheme://127.0.0.1:$port"
                    ok "using $PROXY_URL (github.com -> HTTP $code)"
                    break 2 ;;
            esac
        done
    done
else
    info "no local proxy port is listening"
fi

if [ -z "$PROXY_URL" ]; then
    if curl -fsS --max-time 12 -o /dev/null https://github.com/ 2>/dev/null; then
        ok "no proxy needed - github.com is directly reachable"
    else
        warn "no proxy and no direct route to github.com"
        warn "switching on the VPN and re-running is the reliable fix"
    fi
fi

if [ -n "$PROXY_URL" ]; then
    export http_proxy="$PROXY_URL" https_proxy="$PROXY_URL" all_proxy="$PROXY_URL"
    export HTTP_PROXY="$PROXY_URL" HTTPS_PROXY="$PROXY_URL" ALL_PROXY="$PROXY_URL"
    printf '%s\n' "$PROXY_URL" > "$HOME/.proxy-url"
    ok "exported for this run, and saved to ~/.proxy-url"

    # apt does not read the *_proxy variables for its own transport; it needs the config file.
    mkdir -p "$PREFIX/etc/apt/apt.conf.d"
    cat > "$PREFIX/etc/apt/apt.conf.d/95proxy" <<EOF
Acquire::http::Proxy "$PROXY_URL";
Acquire::https::Proxy "$PROXY_URL";
EOF
    ok "apt configured to use it"

    # git needs its own setting, and only for https - a global http.proxy would break the
    # local repositories the user already has.
    git config --global http.https://github.com/.proxy "$PROXY_URL" 2>/dev/null && \
        ok "git configured for github.com only"
    # pip honours the environment variables above, so nothing else is needed for it.
fi

# -------------------- mirror (fallback only) --------------------

if [ -n "$PROXY_URL" ] || [ "$NO_MIRROR" = "1" ]; then
    say "Package mirror"
    if [ -n "$PROXY_URL" ]; then
        ok "left alone - the proxy reaches the default mirror"
    else
        ok "left alone (--no-mirror)"
    fi
else
    say "Package mirror (no proxy, so a reachable one is needed)"
    # The default is mirror.mephi.ru, in Russia, which does not answer from mainland China;
    # `pkg` then fails with "None of the mirrors are accessible".
    CHOSEN=""
    for m in \
        "https://mirrors.tuna.tsinghua.edu.cn/termux/apt/termux-main" \
        "https://mirrors.ustc.edu.cn/termux/apt/termux-main" \
        "https://mirror.nju.edu.cn/termux/apt/termux-main" \
        "https://packages.termux.dev/apt/termux-main" ; do
        info "trying $m"
        if curl -fsS --max-time 15 -o /dev/null "$m/dists/stable/Release" 2>/dev/null; then
            CHOSEN="$m"
            ok "reachable: $m"
            break
        fi
    done
    if [ -z "$CHOSEN" ]; then
        warn "none answered - leaving the configuration alone"
    else
        mkdir -p "$PREFIX/etc/apt/sources.list.d"
        printf 'deb %s stable main\n' "$CHOSEN" > "$PREFIX/etc/apt/sources.list.d/termux-main.list"
        [ -f "$PREFIX/etc/apt/sources.list" ] && \
            grep -v '^deb ' "$PREFIX/etc/apt/sources.list" > "$PREFIX/etc/apt/sources.list.tmp" 2>/dev/null && \
            mv "$PREFIX/etc/apt/sources.list.tmp" "$PREFIX/etc/apt/sources.list"
        ok "mirror configured"
    fi
fi

# -------------------- packages --------------------

say "Packages"
export DEBIAN_FRONTEND=noninteractive
# **`pkg upgrade` is deliberately NOT run.** It hung the first install: this device had 74
# packages to upgrade, and dpkg asks about configuration-file conflicts even under
# DEBIAN_FRONTEND=noninteractive - with no terminal to answer it waits forever at
# "Building dependency tree...". Measured: six minutes, prefix stuck at 81 MB, no .deb cached.
# It is also unnecessary, since `pkg install` resolves what it needs.
DPKG_OPTS="-o Dpkg::Options::=--force-confold -o Dpkg::Options::=--force-confdef -o Dpkg::Use-Pty=0"

if [ -e "$PREFIX/var/lib/dpkg/lock" ] || [ -e "$PREFIX/var/lib/dpkg/lock-frontend" ]; then
    info "clearing stale dpkg locks from an interrupted run"
    rm -f "$PREFIX/var/lib/dpkg/lock" "$PREFIX/var/lib/dpkg/lock-frontend" \
          "$PREFIX/var/lib/apt/lists/lock" "$PREFIX/var/cache/apt/archives/lock" 2>/dev/null || true
fi
info "finishing any half-configured packages"
dpkg --configure -a >/dev/null 2>&1 || true

pkg update -y 2>&1 | tail -n 5
# shellcheck disable=SC2086
pkg install -y $DPKG_OPTS python git clang make libjpeg-turbo libpng freetype openssl libffi proot-distro 2>&1 | tail -n 15
command -v python >/dev/null || die "python did not install"
ok "python $(python --version 2>&1 | awk '{print $2}')"

say "Python packages"
python -m pip install --upgrade pip 2>&1 | tail -n 2
python -m pip install python-telegram-bot httpx pillow gallery-dl python-dotenv 2>&1 | tail -n 6
ok "installed"

# -------------------- project --------------------

say "Project"
if [ -d "$CLONE_DIR/.git" ]; then
    info "already cloned; updating"
    git -C "$CLONE_DIR" pull --ff-only 2>&1 | tail -n 3
else
    # --depth 1 keeps it small over a phone connection.
    git clone --depth 1 "$REPO_URL" "$CLONE_DIR" || die "git clone failed"
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

    If you set a proxy above, keep it for future sessions by adding to ~/.bashrc:

        export http_proxy=$(cat ~/.proxy-url)
        export https_proxy=$http_proxy
        export all_proxy=$http_proxy
NEXT

#!/data/data/com.termux/files/usr/bin/bash
# Termux bootstrap — run this from inside the Termux app.
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/YuNaiAFK/twitter_pixiv_tg_bot_android/main/scripts/termux-bootstrap.sh)
#
# Why it has to be run in the app and not pushed over adb: Android grants network access per
# process, keyed on the SELinux domain. Termux's own process runs as
# `u:r:untrusted_app_27:s0:c209,...` and has it; a process started with `su 10209` from adb
# lands in `u:r:magisk:s0` and does not - measured, `socket: Permission denied` for every
# connection, including a bare `ping 8.8.8.8`. No amount of adb work changes that.
#
# This script is written to survive the two things that actually go wrong here:
#
#   * the default Termux mirror is mirror.mephi.ru (Russia), unreachable from mainland China,
#     which makes `pkg` fail with "None of the mirrors are accessible"
#   * a long package download over a phone connection, which can drop mid-way

set -u

REPO_URL="${REPO_URL:-https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android.git}"
CLONE_DIR="${CLONE_DIR:-$HOME/twitter_pixiv_tg_bot}"
WITH_SERVER=1

for arg in "$@"; do
    case "$arg" in
        --no-server) WITH_SERVER=0 ;;
        --repo=*)    REPO_URL="${arg#--repo=}" ;;
    esac
done

say()  { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
ok()   { printf '    \033[32m✓\033[0m %s\n' "$1"; }
info() { printf '    \033[36m·\033[0m %s\n' "$1"; }
warn() { printf '    \033[33m!\033[0m %s\n' "$1"; }
die()  { printf '    \033[31m✗ %s\033[0m\n' "$1" >&2; exit 1; }

# -------------------- mirror --------------------

say "Package mirror"
# Test the candidates and keep the first that answers. `pkg` picks a random mirror otherwise,
# and on this network the default is unreachable.
MIRRORS=(
    "https://mirrors.tuna.tsinghua.edu.cn/termux/apt/termux-main"
    "https://mirrors.ustc.edu.cn/termux/apt/termux-main"
    "https://mirror.nju.edu.cn/termux/apt/termux-main"
    "https://packages.termux.dev/apt/termux-main"
    "https://packages-cf.termux.dev/apt/termux-main"
)
CHOSEN=""
for m in "${MIRRORS[@]}"; do
    info "trying $m"
    if curl -fsS --max-time 15 -o /dev/null "$m/dists/stable/Release" 2>/dev/null; then
        CHOSEN="$m"
        ok "reachable: $m"
        break
    fi
done

if [ -z "$CHOSEN" ]; then
    warn "no mirror answered - leaving the configuration alone"
    warn "if pkg fails, set one by hand with: termux-change-repo"
else
    mkdir -p "$PREFIX/etc/apt/sources.list.d"
    printf 'deb %s stable main\n' "$CHOSEN" > "$PREFIX/etc/apt/sources.list.d/termux-main.list"
    # Blank the default entry so the unreachable one is not used as a fallback.
    if [ -f "$PREFIX/etc/apt/sources.list" ]; then
        grep -v '^deb ' "$PREFIX/etc/apt/sources.list" > "$PREFIX/etc/apt/sources.list.tmp" 2>/dev/null || true
        mv "$PREFIX/etc/apt/sources.list.tmp" "$PREFIX/etc/apt/sources.list"
    fi
    ok "mirror configured"
fi

# -------------------- packages --------------------

say "Packages"
export DEBIAN_FRONTEND=noninteractive
pkg update -y 2>&1 | tail -n 5
# clang/make plus the image libraries are Pillow's build dependencies; without them pip
# compiles from source and fails on missing headers instead of using a wheel.
pkg install -y python git clang make libjpeg-turbo libpng freetype openssl libffi proot-distro 2>&1 | tail -n 12
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
    git clone --depth 1 "$REPO_URL" "$CLONE_DIR" || die "git clone failed"
fi
cd "$CLONE_DIR" || die "cannot enter $CLONE_DIR"
ok "at $CLONE_DIR"

if [ -f .env ]; then
    info ".env exists - not touched"
else
    if [ -f .env.example ]; then
        cp .env.example .env
        warn ".env created - fill in BOT_TOKEN and ADMIN_USER_IDS before starting"
    fi
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
NEXT

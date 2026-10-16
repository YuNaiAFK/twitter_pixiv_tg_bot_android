#!/data/data/com.termux/files/usr/bin/bash
# Install files staged at /data/local/tmp/botstage into the project.
#
#   bash scripts/install-staged.sh              # everything staged
#   bash scripts/install-staged.sh bot.py ehentai.py
#
# **Why this exists as a script rather than a one-liner.**
#
# The deploy used to be `adb shell "su -c 'tr -d \"\r\" < a > b'"`. Through PowerShell, then the
# shell, then su, the quoting collapsed and tr received the literal letter r instead of the escape
# \r - so it deleted every "r" in the file. `background` became `backgound`, `if value < 1024 or
# unit` became `ifvalue<1024ounit`, and the module stopped importing. Nothing in the command
# looked wrong.
#
# Inside this file the single quotes survive every layer, tr gets a real backslash-r, and only
# carriage returns are removed.
#
# Every install is followed by a syntax check and a hash comparison against the staged copy, so a
# corrupted deploy fails here instead of at the next bot restart.
set -u
export HOME="${HOME:-/data/data/com.termux/files/home}"
export PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="/data/local/tmp/botstage"

# staged name -> path relative to the project
declare -A TARGETS=(
    [bot_bot.py]="bot/bot.py"
    [bot_ehentai.py]="bot/ehentai.py"
    [bot_pixiv_login.py]="bot/pixiv_login.py"
    [bot_platform_support.py]="bot/platform_support.py"
    [bot_tag_translations.py]="bot/tag_translations.py"
    [bot_test_characterization.py]="bot/test_characterization.py"
    [control_panel.py]="control/panel.py"
    [control_index.html]="control/index.html"
    [scripts_start-all.sh]="scripts/start-all.sh"
    [scripts_run-bot.sh]="scripts/run-bot.sh"
    [scripts_run-server.sh]="scripts/run-server.sh"
    [scripts_boot-services.sh]="scripts/boot-services.sh"
    [scripts_enable-external-apps.sh]="scripts/enable-external-apps.sh"
    [scripts_install-staged.sh]="scripts/install-staged.sh"
    [scripts_check-images.sh]="scripts/check-images.sh"
    [scripts_check-page-images.sh]="scripts/check-page-images.sh"
    [VERSION.properties]="VERSION.properties"
)

# Optional arguments: staged basenames without the directory-mangling prefix, or the staged names.
wanted=()
for arg in "$@"; do
    case "$arg" in
        bot.py) wanted+=("bot_bot.py") ;;
        ehentai.py) wanted+=("bot_ehentai.py") ;;
        panel.py) wanted+=("control_panel.py") ;;
        index.html) wanted+=("control_index.html") ;;
        start-all.sh) wanted+=("scripts_start-all.sh") ;;
        check-images.sh) wanted+=("scripts_check-images.sh") ;;
        check-page-images.sh) wanted+=("scripts_check-page-images.sh") ;;
        install-staged.sh) wanted+=("scripts_install-staged.sh") ;;
        VERSION.properties) wanted+=("VERSION.properties") ;;
        *) wanted+=("$arg") ;;
    esac
done

staged=()
if [ "${#wanted[@]}" -eq 0 ]; then
    for name in "${!TARGETS[@]}"; do
        [ -f "$STAGE/$name" ] && staged+=("$name")
    done
else
    for name in "${wanted[@]}"; do
        if [ -f "$STAGE/$name" ]; then
            staged+=("$name")
        else
            echo "  MISSING $STAGE/$name"
        fi
    done
fi

if [ "${#staged[@]}" -eq 0 ]; then
    echo "nothing staged at $STAGE"
    exit 1
fi

echo "=== installing ${#staged[@]} file(s) ==="
failed=0
for name in "${staged[@]}"; do
    rel="${TARGETS[$name]:-}"
    if [ -z "$rel" ]; then
        echo "  no target known for $name"
        failed=1
        continue
    fi
    dest="$PROJECT_DIR/$rel"
    mkdir -p "$(dirname "$dest")"

    # **The one line that matters.** A real backslash-r, because the single quotes here are not
    # reinterpreted by anything between the editor and tr.
    tr -d '\r' < "$STAGE/$name" > "$dest"

    case "$rel" in
        *.sh) chmod 755 "$dest" ;;
        *)    chmod 644 "$dest" ;;
    esac

    # Compare what landed against what was staged. A silent mangling is what this catches.
    a=$(tr -d '\r' < "$STAGE/$name" | sha256sum | cut -d' ' -f1)
    b=$(tr -d '\r' < "$dest" | sha256sum | cut -d' ' -f1)
    if [ "$a" != "$b" ]; then
        echo "  FAIL $rel - content does not match the staged copy"
        failed=1
        continue
    fi
    printf '  ok   %-34s %s\n' "$rel" "${a:0:12}"
done

echo
echo "=== syntax ==="
for name in "${staged[@]}"; do
    rel="${TARGETS[$name]:-}"
    case "$rel" in
        *.py)
            if python -m py_compile "$PROJECT_DIR/$rel" 2>/dev/null; then
                printf '  ok   %s\n' "$rel"
            else
                printf '  FAIL %s\n' "$rel"
                python -m py_compile "$PROJECT_DIR/$rel" 2>&1 | tail -4 | sed 's/^/       /'
                failed=1
            fi
            ;;
        *.sh)
            if bash -n "$PROJECT_DIR/$rel" 2>/dev/null; then
                printf '  ok   %s\n' "$rel"
            else
                printf '  FAIL %s\n' "$rel"
                failed=1
            fi
            ;;
    esac
done

echo
if [ "$failed" -eq 0 ]; then
    echo "all files installed and verified"
else
    echo "*** something failed - do not restart the bot until it is fixed ***"
fi
exit "$failed"

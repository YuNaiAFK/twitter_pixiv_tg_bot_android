#!/data/data/com.termux/files/usr/bin/bash
# Install files staged at /data/local/tmp/botstage into the project.
#
#   bash scripts/install-staged.sh                 # everything staged
#   bash scripts/install-staged.sh bot.py ehentai.py
#   bash scripts/install-staged.sh bot_bot.py      # the staged name also works
#
# **Why this exists as a script rather than a one-liner.**
#
# The deploy used to be `adb shell "su -c 'tr -d \"\r\" < a > b'"`. Through PowerShell, then the
# shell, then su, the quoting collapsed and tr stopped receiving the escape \r. Twice it destroyed
# a file: once deleting every "r" (`background` became `backgound`), once every space
# (`if value < 1024 or unit` became `ifvalue<1024ounit`). Both commands looked correct. Inside this
# file the single quotes survive every layer, so tr gets a real backslash-r.
#
# Every install is followed by a hash comparison against the staged copy and a syntax check, so a
# corrupted deploy fails here instead of at the next bot restart.
#
# **Names are derived, not listed.** The staging convention is the directory as a prefix -
# `bot/bot.py` is staged as `bot_bot.py` - so the target is the first underscore replaced by a
# slash. This used to be two hand-maintained maps, and every new file needed both of them updated;
# forgetting meant a deploy that silently did nothing.
set -u
export HOME="${HOME:-/data/data/com.termux/files/home}"
export PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="/data/local/tmp/botstage"

# Staged name -> path relative to the project: the first underscore becomes a slash.
#   bot_bot.py -> bot/bot.py            scripts_check-images.sh -> scripts/check-images.sh
#   VERSION.properties -> VERSION.properties (no underscore, left alone)
derive_target() {
    case "$1" in
        *_*) printf '%s/%s\n' "${1%%_*}" "${1#*_}" ;;
        *)   printf '%s\n' "$1" ;;
    esac
}

# A bare filename resolves to whichever staged file targets it.
find_staged_for() {
    local want="$1" name rel
    for path in "$STAGE"/*; do
        [ -f "$path" ] || continue
        name="$(basename "$path")"
        rel="$(derive_target "$name")"
        case "$rel" in
            */"$want") printf '%s\n' "$name"; return 0 ;;
        esac
    done
    return 1
}

staged=()
if [ "$#" -eq 0 ]; then
    for path in "$STAGE"/*; do
        [ -f "$path" ] && staged+=("$(basename "$path")")
    done
else
    for arg in "$@"; do
        if [ -f "$STAGE/$arg" ]; then
            staged+=("$arg")
        elif name="$(find_staged_for "$arg")"; then
            staged+=("$name")
        else
            echo "  MISSING nothing staged matches '$arg'"
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
    rel="$(derive_target "$name")"
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
    rel="$(derive_target "$name")"
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
                bash -n "$PROJECT_DIR/$rel" 2>&1 | tail -4 | sed 's/^/       /'
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

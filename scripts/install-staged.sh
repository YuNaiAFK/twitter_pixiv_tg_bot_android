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

# Every staged file whose target ends in the given path, or whose target *is* it.
#
# **This returns all matches, and the caller refuses when there is more than one.**
#
# It used to return the first, and the argument handling tried an exact staged name before this
# function at all. Together those produced a silent wrong install: a stale `bot.py` left in the
# staging directory meant `install-staged.sh bot.py` matched it directly, `derive_target("bot.py")`
# is `bot.py` with no underscore to split, and the file went to the project root instead of
# `bot/bot.py`. The hash check passed because it compared the staged copy against the copy it had
# just written - so a deploy reported success while changing nothing, and three bot.py fixes were
# "installed" without ever reaching the device.
find_staged_matches() {
    local want="$1" name rel
    for path in "$STAGE"/*; do
        [ -f "$path" ] || continue
        name="$(basename "$path")"
        rel="$(derive_target "$name")"
        if [ "$rel" = "$want" ] || [ "${rel%/"$want"}" != "$rel" ]; then
            printf '%s\n' "$name"
        fi
    done
}

staged=()
# Initialised before the argument loop: it used to be set to 0 after it, which wiped out the
# "MISSING" and "AMBIGUOUS" failures the loop had just recorded and let a bad deploy report success.
failed=0
if [ "$#" -eq 0 ]; then
    for path in "$STAGE"/*; do
        [ -f "$path" ] && staged+=("$(basename "$path")")
    done
else
    for arg in "$@"; do
        matches="$(find_staged_matches "$arg")"
        count=$(printf '%s' "$matches" | grep -c . || true)

        if [ "$count" -gt 1 ]; then
            echo "  AMBIGUOUS '$arg' matches more than one staged file:"
            printf '%s\n' "$matches" | sed 's/^/      /'
            echo "      pass the staged name instead, e.g. $(printf '%s' "$matches" | head -1)"
            failed=1
            continue
        fi

        if [ "$count" -eq 1 ]; then
            staged+=("$matches")
        elif [ -f "$STAGE/$arg" ]; then
            # Not reachable by target and present by name: a staged name that carries no directory —
            # VERSION.properties is the one real case.
            staged+=("$arg")
        else
            echo "  MISSING nothing staged matches '$arg'"
            failed=1
        fi
    done
fi

if [ "${#staged[@]}" -eq 0 ]; then
    echo "nothing staged at $STAGE"
    exit 1
fi

echo "=== installing ${#staged[@]} file(s) ==="
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
    # The absolute destination, on its own line. When the target is wrong this is the one thing that
    # makes it visible: the bug that prompted it wrote `<project>/bot.py` instead of
    # `<project>/bot/bot.py` and reported "ok bot.py" both times.
    printf '         -> %s\n' "$dest"
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

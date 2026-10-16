#!/data/data/com.termux/files/usr/bin/bash
# Run a command and write its output where it can be read afterwards.
#
#   bash scripts/run-and-report.sh <output-file> <command> [args...]
#
# **Why this exists.** The only way to run something in Termux's own SELinux domain from adb is a
# RUN_COMMAND intent, and that has no way to return stdout - it goes to the app, not to adb. So a
# command that works perfectly reports nothing, and a command that fails reports nothing too.
#
# Writing to a file and reading it back through adb fixes that, and it is what every probe in this
# project has been doing by hand. This makes it one call.
#
# Along with the output it records the exit code and the SELinux domain, because a network failure
# in the wrong domain is the single most misleading thing about debugging here: a process started
# with `su 10209` lands in u:r:magisk:s0, where sockets cannot be created, so every request fails
# with a connect error and working code looks broken.
set -u
export HOME="${HOME:-/data/data/com.termux/files/home}"
export PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"

if [ "$#" -lt 2 ]; then
    echo "usage: $0 <output-file> <command> [args...]" >&2
    exit 2
fi

OUT="$1"
shift

# Resolve a relative output path against the project, so callers can pass data/whatever.txt.
case "$OUT" in
    /*) ;;
    *)  OUT="$HOME/twitter_pixiv_tg_bot/$OUT" ;;
esac

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo "  domain: $(cat /proc/self/attr/current 2>/dev/null | tr -d '\0')"
    echo "  cwd:    $(pwd)"
    echo "  cmd:    $*"
    echo
    echo "--- output ---"
    "$@"
    code=$?
    echo
    echo "--- exit: $code ---"
} > "$OUT" 2>&1

exit 0

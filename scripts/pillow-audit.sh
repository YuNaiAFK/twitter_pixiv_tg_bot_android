#!/data/data/com.termux/files/usr/bin/bash
# How is Pillow installed, and can it be upgraded?
#
# The answer decides whether the fix is `pip install -U Pillow` or something else: a wheel for
# android-aarch64 is not published, so the phone is almost certainly running a source build - and a
# source build of a C extension needs the toolchain, which is not the same operation as pip upgrading
# a pure-Python package.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
OUT="$HOME/twitter_pixiv_tg_bot/data/pillow-audit.txt"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo
    echo "--- what is installed and how ---"
    python -m pip show Pillow 2>/dev/null | sed 's/^/  /'
    echo
    echo "--- the compiled extension ---"
    python - <<'PY'
import PIL, os
from PIL import Image
print(f"  PIL version:   {PIL.__version__}")
print(f"  PIL path:      {os.path.dirname(PIL.__file__)}")
print(f"  core module:   {getattr(Image.core, '__file__', '?')}")
print(f"  is a .so:      {str(getattr(Image.core, '__file__', '')).endswith('.so')}")
print(f"  built from:    {'source' if not getattr(Image.core, '__file__', '').endswith('.so') else 'extension'}")
PY
    echo
    echo "--- is a C compiler available, for a source upgrade ---"
    for tool in clang gcc cc meson ninja pkg-config; do
        if command -v "$tool" >/dev/null 2>&1; then
            printf '  %-12s %s\n' "$tool" "$(command -v "$tool")"
        else
            printf '  %-12s (not found)\n' "$tool"
        fi
    done
    echo
    echo "--- what pip would install ---"
    python -m pip index versions Pillow 2>&1 | head -4 | sed 's/^/  /'
    echo
    echo "--- can it reach the index at all ---"
    timeout 30 python -m pip download Pillow==13.0.0 --no-deps --dest /tmp/pillowprobe 2>&1 | tail -4 | sed 's/^/  /'
    ls -la /tmp/pillowprobe 2>/dev/null | sed 's/^/  /'
    rm -rf /tmp/pillowprobe
} > "$OUT" 2>&1

echo "written to $OUT"

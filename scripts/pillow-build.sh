#!/data/data/com.termux/files/usr/bin/bash
# Diagnose and then fix the Pillow build.
#
# The first attempt used --no-build-isolation, which was the wrong direction: that flag tells pip to
# use the build backend already installed in this environment, and Termux's Python does not ship
# setuptools. The result was BackendUnavailable: Cannot import 'backend' - pip could not find the
# thing it had been told not to install.
#
# The right approach is the opposite: let pip install setuptools and wheel into an isolated build
# environment, which it can do from the index. That also means the toolchain has to be reachable from
# that isolated environment, which is why CC/CFLAGS are exported explicitly rather than inherited -
# a build environment gets a minimal PATH.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
export TMPDIR="$PREFIX/tmp"
OUT="$HOME/twitter_pixiv_tg_bot/data/pillow-build.txt"
mkdir -p "$TMPDIR" 2>/dev/null

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo

    echo "--- is setuptools present in this environment ---"
    python - <<'PY'
for name in ("setuptools", "wheel", "pip"):
    try:
        mod = __import__(name)
        print(f"  {name:12} {getattr(mod, '__version__', '?')}")
    except Exception as exc:
        print(f"  {name:12} MISSING ({type(exc).__name__})")
PY
    echo

    echo "--- the compiler pip would use ---"
    echo "  CC=${CC:-(unset)}"
    echo "  PATH has cc: $(command -v cc || echo no)"
    echo "  clang: $(command -v clang || echo no)"
    echo "  python-config: $(command -v python3-config || command -v python-config || echo no)"
    echo

    echo "--- installing Pillow 13 with build isolation and an explicit compiler ---"
    export CC="$PREFIX/bin/clang"
    export CXX="$PREFIX/bin/clang++"
    export CFLAGS="-I$PREFIX/include"
    export LDFLAGS="-L$PREFIX/lib"
    timeout 2400 python -m pip install --upgrade --no-cache-dir \
        Pillow==13.0.0 2>&1 \
        | tail -30 | sed 's/^/  /'
    echo

    echo "--- result ---"
    python - <<'PY'
try:
    from PIL import Image
    import PIL
    print(f"  PIL version: {PIL.__version__}")
except Exception as exc:
    print(f"  import failed: {type(exc).__name__}: {exc}")
PY
} > "$OUT" 2>&1

echo "written to $OUT"

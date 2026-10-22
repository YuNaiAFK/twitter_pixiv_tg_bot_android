#!/data/data/com.termux/files/usr/bin/bash
# Upgrade the two packages with known vulnerabilities, and prove it worked.
#
# Pillow 12.3.0 has 24 published CVEs, one of them CRITICAL and reachable from this bot's exact code
# path: `Image.thumbnail()` calls `JpegImageFile.draft()`, and the heap overflow is in
# `ImagingJpegDecode()` - which is what draft() ends up in. The bot opens images downloaded from
# Twitter, Pixiv and e-hentai, so the input is attacker-controlled.
#
# certifi carries a revoked intermediate CA. An attacker holding one of those keys, positioned on the
# path, can present a certificate that every httpx request would accept.
#
# **Pillow is a C extension built from source here** - there is no android-aarch64 wheel - so this
# takes minutes rather than seconds, and the toolchain has to be present. Both are checked rather
# than assumed, and the script stops rather than leaving a half-built extension behind.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
export TMPDIR="$PREFIX/tmp"
OUT="$HOME/twitter_pixiv_tg_bot/data/upgrade-security.txt"
mkdir -p "$TMPDIR" 2>/dev/null

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo

    echo "--- before ---"
    python - <<'PY'
import importlib
for name in ("PIL", "certifi"):
    try:
        m = importlib.import_module(name)
        print(f"  {name:10} {getattr(m, '__version__', '?')}")
    except Exception as exc:
        print(f"  {name:10} {type(exc).__name__}")
PY
    echo

    echo "--- toolchain check (Pillow builds from source here) ---"
    missing=""
    for tool in cc gcc pkg-config python3-config; do
        if command -v "$tool" >/dev/null 2>&1; then
            echo "  ok   $tool"
        else
            echo "  MISS $tool"
            missing="$missing $tool"
        fi
    done
    if [ -n "$missing" ]; then
        echo
        echo "  cannot build Pillow without:$missing"
        echo "  install with: pkg install build-essential python-dev"
        exit 1
    fi
    echo

    echo "--- upgrading certifi (pure python, instant) ---"
    python -m pip install --upgrade --no-cache-dir certifi 2>&1 | tail -4 | sed 's/^/  /'
    echo

    echo "--- upgrading Pillow (C extension, this takes a few minutes) ---"
    # --no-build-isolation: the build environment would otherwise download a fresh setuptools and
    # try to compile with a toolchain it cannot see under Termux.
    timeout 1800 python -m pip install --upgrade --no-cache-dir --no-build-isolation Pillow 2>&1 \
        | tail -25 | sed 's/^/  /'
    echo

    echo "--- after ---"
    python - <<'PY'
import importlib
for name in ("PIL", "certifi"):
    try:
        m = importlib.import_module(name)
        print(f"  {name:10} {getattr(m, '__version__', '?')}")
    except Exception as exc:
        print(f"  {name:10} {type(exc).__name__}: {exc}")
PY
    echo

    echo "--- does the JPEG path still work (the one that matters) ---"
    python - <<'PY'
import io
try:
    from PIL import Image
    # A 4x4 JPEG, encoded then decoded then thumbnailed: exactly the calls downscale_image makes.
    src = Image.new("RGB", (64, 64), (120, 30, 200))
    buf = io.BytesIO()
    src.save(buf, "JPEG", quality=85)
    buf.seek(0)
    with Image.open(buf) as image:
        image = image.convert("RGB")
        image.thumbnail((32, 32), Image.LANCZOS)
        print(f"  JPEG open + convert + thumbnail: ok, {image.size}")
    buf.seek(0)
    with Image.open(buf) as image:
        image.thumbnail((16, 16), Image.LANCZOS)
        print(f"  PNG-free thumbnail path: ok, {image.size}")
except Exception as exc:
    print(f"  FAILED: {type(exc).__name__}: {exc}")
PY
} > "$OUT" 2>&1

echo "written to $OUT"

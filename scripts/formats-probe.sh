#!/data/data/com.termux/files/usr/bin/bash
# Does Image.open accept a format allowlist, and does it actually refuse the dangerous ones?
#
# An allowlist is better than a blocklist: the exotic decoders - EPS (which shells out to
# Ghostscript), XBM (ReDoS), MSP, MIC, PDF - are where the recent CVEs live, and a new one appears in
# one of them often enough that not loading them at all is worth more than the formats being safe
# today. Verified rather than assumed, because a keyword that does not exist would raise TypeError at
# runtime and the bot would silently stop downscaling anything.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
OUT="$HOME/twitter_pixiv_tg_bot/data/formats-probe.txt"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo
    python - <<'PY'
import inspect
import io
from PIL import Image

print(f"  Pillow {getattr(__import__('PIL'), '__version__', '?')}")
sig = inspect.signature(Image.open)
print(f"  Image.open{sig}")
print(f"  supports formats=: {'formats' in sig.parameters}")
print()

# Build one valid JPEG and confirm an allowlisted open still works.
buf = io.BytesIO()
Image.new("RGB", (32, 32), (10, 20, 30)).save(buf, "JPEG")
jpeg = buf.getvalue()

ALLOWED = ["JPEG", "PNG", "GIF", "WEBP", "BMP"]
for label, data in (("JPEG", jpeg),
                    ("EPS", b"%!PS-Adobe-3.0 EPSF-3.0\n%%BoundingBox: 0 0 10 10\n"),
                    ("XBM", b"#define test_width 1\n#define test_height 1\nstatic char test_bits[] = {0x00};"),
                    ("PS", b"%!PS-Adobe-3.0\n"),
                    ("PDF", b"%PDF-1.4\n1 0 obj\n<<>>\nendobj\n")):
    try:
        with Image.open(io.BytesIO(data), formats=ALLOWED) as im:
            print(f"  {label:5} accepted -> {im.format} {im.size}")
    except Exception as exc:
        print(f"  {label:5} refused  -> {type(exc).__name__}: {str(exc)[:60]}")
PY
} > "$OUT" 2>&1

echo "written to $OUT"

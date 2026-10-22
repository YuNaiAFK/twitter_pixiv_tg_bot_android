#!/data/data/com.termux/files/usr/bin/bash
# Verify the hardened downscale_image: real images work, disguised non-images are refused.
#
# The failure this guards against is silent. `downscale_image` catches every exception and returns
# None, and the caller then sends a document instead of a photo - so a NameError from a missing
# constant, or a TypeError from an unsupported keyword, would look exactly like "Pillow is not
# installed" and nobody would notice the protection had gone.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
OUT="$HOME/twitter_pixiv_tg_bot/data/hardening.txt"
cd "$HOME/twitter_pixiv_tg_bot/bot" || exit 1

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo
    python - <<'PY'
import io
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, ".")
sys.path.insert(0, "vendor")

import bot
from PIL import Image

print(f"  Pillow: {Image.__version__ if hasattr(Image, '__version__') else '?'}")
print(f"  PILLOW_FORMATS = {bot.PILLOW_FORMATS}")
print()

with tempfile.TemporaryDirectory() as tmp:
    work = Path(tmp)

    # 1. A real oversized JPEG must still be downscaled - the protection must not break the feature.
    big = work / "big.jpg"
    Image.new("RGB", (4000, 3000), (30, 60, 90)).save(big, "JPEG", quality=95)
    out = bot.downscale_image(big, work, max_edge=1024)
    if out is None:
        print(f"  正常 JPEG: FAILED (returned None - the feature is broken)")
    else:
        size = Image.open(out).size
        print(f"  正常 JPEG: ok, {big.stat().st_size // 1024} KB -> {out.stat().st_size // 1024} KB, {size}")

    # 2. A PNG too, because the allowlist must not accidentally exclude the common case.
    png = work / "pic.png"
    Image.new("RGBA", (2000, 2000), (200, 100, 50, 255)).save(png, "PNG")
    out_png = bot.downscale_image(png, work, max_edge=512)
    print(f"  正常 PNG:  {'ok, ' + str(Image.open(out_png).size) if out_png else 'FAILED'}")

    # 3. Disguised non-images must be refused. Each of these is a decoder with a recent CVE.
    payloads = {
        "EPS": b"%!PS-Adobe-3.0 EPSF-3.0\n%%BoundingBox: 0 0 10 10\n",
        "XBM": b"#define t_width 1\n#define t_height 1\nstatic char t_bits[] = {0x00};",
        "PDF": b"%PDF-1.4\n1 0 obj\n<<>>\nendobj\n",
        "MSP": b"DanM\n\x00\x00\x00\x00",
    }
    refused = 0
    for name, data in payloads.items():
        target = work / f"disguised-{name}.jpg"
        target.write_bytes(data)
        result = bot.downscale_image(target, work, max_edge=256)
        if result is None:
            refused += 1
            print(f"  偽裝 {name}: 被拒絕 ✅")
        else:
            print(f"  偽裝 {name}: 竟然被接受 ❌ ({result})")
    print()
    print(f"  拒絕 {refused}/{len(payloads)}")
PY
} > "$OUT" 2>&1

echo "written to $OUT"

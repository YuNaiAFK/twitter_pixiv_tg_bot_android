#!/usr/bin/env python3
"""
Draw the launcher icons for the control app.

Generated rather than committed as binaries so the artwork can be changed by editing numbers
here, and so the same shape can be produced at every density the launcher asks for.

One image is written per density: Android picks the closest match, and shipping only one size
makes the launcher upscale it, which looks soft on a high-density screen.
"""

from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:  # pragma: no cover - the bundled environment has Pillow
    raise SystemExit("Pillow is required: run this with the project's Python")

HERE = Path(__file__).resolve().parent
OUT = HERE / "res"

# Density -> icon size in pixels. These are the standard launcher sizes.
DENSITIES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}

BG = (15, 17, 21)          # the panel's --bg
CARD = (23, 26, 33)        # --card
BLUE = (79, 140, 255)      # --accent
GREEN = (53, 192, 122)     # --ok
GREY = (139, 147, 167)     # --dim


def draw_icon(size: int) -> Image.Image:
    """A terminal window with a prompt line, matching the control panel's look."""
    image = Image.new("RGBA", (size, size), BG + (255,))
    draw = ImageDraw.Draw(image)

    unit = size / 48.0
    radius = max(1, int(7 * unit))

    # Rounded card
    pad = int(6 * unit)
    draw.rounded_rectangle(
        [pad, pad, size - pad, size - pad],
        radius=radius, fill=CARD, outline=(39, 44, 55, 255), width=max(1, int(unit)),
    )

    # Two blue dots as "eyes", the same motif as the web panel's manifest icon
    r = max(1, int(1.6 * unit))
    for cx in (int(17 * unit), int(31 * unit)):
        cy = int(18 * unit)
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=BLUE)

    # A green prompt bar under them, which is what makes it read as a terminal rather than a
    # face. Kept as one stroke: an earlier version added a second, diagonal line and the result
    # looked like a stray pen mark rather than a log.
    draw.line(
        [int(15 * unit), int(28 * unit), int(33 * unit), int(28 * unit)],
        fill=GREEN, width=max(2, int(2.4 * unit)),
    )

    # One dim line beneath, shorter, standing in for more output.
    draw.line(
        [int(15 * unit), int(35 * unit), int(26 * unit), int(35 * unit)],
        fill=GREY, width=max(1, int(1.6 * unit)),
    )

    return image


def main() -> int:
    written = []
    for density, size in DENSITIES.items():
        folder = OUT / f"mipmap-{density}"
        folder.mkdir(parents=True, exist_ok=True)
        path = folder / "ic_launcher.png"
        draw_icon(size).save(path, "PNG", optimize=True)
        written.append(f"  {path.relative_to(OUT.parent)}  ({size}x{size})")
    print("wrote:")
    for line in written:
        print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

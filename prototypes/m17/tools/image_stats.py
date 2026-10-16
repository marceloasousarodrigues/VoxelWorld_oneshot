"""Objective statistics for Godot screenshot captures.

Usage:
    python prototypes/m17/tools/image_stats.py <image> [image ...]

The Godot capture harness renders from inside the running game, but "the file
exists" is not evidence that the render looks right.  This tool makes the visual
claims measurable: it reports the mean colour, a coarse grid of tile colours,
saturation, how much of the frame is near-black (crushed shadows) and how much
is near-white (blown highlights).

This is a measurement tool, not a substitute for looking at the image.
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image


def _mean(region: Image.Image) -> tuple[float, float, float]:
    stat = region.resize((1, 1), Image.BOX).getpixel((0, 0))
    return (float(stat[0]), float(stat[1]), float(stat[2]))


def _saturation(rgb: tuple[float, float, float]) -> float:
    hi = max(rgb)
    lo = min(rgb)
    return 0.0 if hi <= 0 else (hi - lo) / hi


def describe(path: Path, grid: tuple[int, int] = (6, 4)) -> None:
    image = Image.open(path).convert("RGB")
    width, height = image.size
    mean = _mean(image)

    # Crushed shadows / blown highlights, as a share of the frame.
    # 1/255-step luminance histogram is enough at this fidelity.
    small = image.resize((width // 4, height // 4), Image.BOX)
    # Pillow >= 12 deprecates `getdata` in favour of `get_flattened_data`.
    pixels = list(
        small.get_flattened_data() if hasattr(small, "get_flattened_data") else small.getdata()
    )
    total = len(pixels)
    black = sum(1 for p in pixels if max(p) <= 24)
    white = sum(1 for p in pixels if min(p) >= 235)
    # "Washed out" = low saturation mid/high brightness (fog/haze over terrain).
    washed = sum(1 for p in pixels if min(p) > 140 and _saturation(p) < 0.14)

    print(f"== {path.name}  {width}x{height}")
    print(
        "   mean rgb %3.0f %3.0f %3.0f   sat %.2f   crushed %.1f%%   blown %.1f%%   hazy %.1f%%"
        % (
            mean[0],
            mean[1],
            mean[2],
            _saturation(mean),
            100.0 * black / total,
            100.0 * white / total,
            100.0 * washed / total,
        )
    )
    cols, rows = grid
    print(f"   {cols}x{rows} tile means (rows top->bottom):")
    for row in range(rows):
        cells = []
        for col in range(cols):
            box = (
                col * width // cols,
                row * height // rows,
                (col + 1) * width // cols,
                (row + 1) * height // rows,
            )
            rgb = _mean(image.crop(box))
            cells.append("%3.0f,%3.0f,%3.0f" % rgb)
        print("     " + " | ".join(cells))


def main(argv: list[str]) -> int:
    paths = [Path(arg) for arg in argv]
    missing = [p for p in paths if not p.is_file()]
    if not paths or missing:
        for path in missing:
            print(f"missing: {path}", file=sys.stderr)
        print(__doc__, file=sys.stderr)
        return 2
    for path in paths:
        describe(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

"""Objective pixel probe for the M17 Godot HUD and the death screen.

Usage:
    python prototypes/m17/tools/hud_probe.py <capture.png> [--expect health|breath|death ...]

`image_stats.py` measures a whole frame.  This tool checks *specific* UI elements
against the colours and rectangles the HUD code actually draws, so a capture can
be verified mechanically: "the health bar is filled to this fraction, the breath
bar exists, the death overlay covers the frame" are counts, not opinions.

Rectangles (1280x720 reference, scaled to the real image size) come from
`scripts/game/game_hud.gd` and `scripts/game/death_screen.gd`:

  health bar   fill (219, 41, 46)   x 18..258   y 602..618
  health track ( 23,  5,  5) @74%   same rect
  breath bar   fill ( 89,184,242)   x 18..198   y 542..552
  breath track (  5, 13, 23) @74%   same rect
  death dim    ( 43,  0,  0) @74% over the frame
  death title  (242, 61, 61)        centre band

Exit status is 0 when every requested expectation holds, 1 otherwise, and 2 for
a usage/file error.
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

REFERENCE = (1280, 720)

HEALTH_FILL = (219, 41, 46)
HEALTH_TRACK = (23, 5, 5)
BREATH_FILL = (89, 184, 242)
BREATH_TRACK = (5, 13, 23)
DEATH_DIM = (43, 0, 0)
DEATH_TITLE = (242, 61, 61)


def _scaled(value: float, total: int, reference: int = REFERENCE[0]) -> int:
    return int(round(value * total / reference))


def _rect(image: Image.Image, x0: float, y0: float, x1: float, y1: float) -> Image.Image:
    width, height = image.size
    return image.crop(
        (
            _scaled(x0, width),
            _scaled(y0, height, REFERENCE[1]),
            _scaled(x1, width),
            _scaled(y1, height, REFERENCE[1]),
        )
    )


def _count(region: Image.Image, colour: tuple[int, int, int], tolerance: int = 26) -> int:
    """Pixels within `tolerance` of `colour` on every channel."""
    target_r, target_g, target_b = colour
    hits = 0
    for red, green, blue in region.get_flattened_data() if hasattr(region, "get_flattened_data") else region.getdata():
        if (
            abs(red - target_r) <= tolerance
            and abs(green - target_g) <= tolerance
            and abs(blue - target_b) <= tolerance
        ):
            hits += 1
    return hits


def _vitals_map(image: Image.Image) -> str:
    """A readable text map of the bottom-left vitals region (18..278 x 500..660)."""
    region = _rect(image, 0, 470, 300, 660).convert("RGB")
    cols, rows = 75, 19
    cell_w = max(1, region.width // cols)
    cell_h = max(1, region.height // rows)
    lines: list[str] = []
    for row in range(rows):
        cells = []
        for col in range(cols):
            box = (
                col * cell_w,
                row * cell_h,
                min(region.width, (col + 1) * cell_w),
                min(region.height, (row + 1) * cell_h),
            )
            tile = region.crop(box)
            r, g, b = tile.resize((1, 1), Image.BOX).getpixel((0, 0))
            if abs(r - HEALTH_FILL[0]) <= 40 and abs(g - HEALTH_FILL[1]) <= 40 and abs(b - HEALTH_FILL[2]) <= 40:
                cells.append("H")
            elif abs(r - BREATH_FILL[0]) <= 45 and abs(g - BREATH_FILL[1]) <= 45 and abs(b - BREATH_FILL[2]) <= 45:
                cells.append("B")
            elif r < 60 and g < 60 and b < 60:
                cells.append(".")
            elif max(r, g, b) > 200:
                cells.append("#")
            else:
                cells.append(" ")
        lines.append("".join(cells))
    return "\n".join(lines)


def _frame_map(image: Image.Image) -> str:
    """A 20x10 text map of the whole frame, to see what the capture actually shows."""
    small = image.resize((20, 10), Image.BOX).convert("RGB")
    lines = []
    for y in range(10):
        row = []
        for x in range(20):
            r, g, b = small.getpixel((x, y))
            if r > 1.5 * max(g, b) and r > 30:
                row.append("R")
            elif max(r, g, b) > 200:
                row.append("#")
            elif max(r, g, b) < 40:
                row.append(".")
            else:
                row.append(" ")
        lines.append("".join(row))
    return "\n".join(lines)


def probe(path: Path, expectations: set[str]) -> bool:
    image = Image.open(path).convert("RGB")
    width, height = image.size
    print(f"== {path.name}  {width}x{height}")

    # --- vitals -------------------------------------------------------------
    health_bar = _rect(image, 18, 602, 258, 618)
    health_fill = _count(health_bar, HEALTH_FILL)
    health_track = _count(health_bar, HEALTH_TRACK)
    breath_bar = _rect(image, 18, 542, 198, 552)
    breath_fill = _count(breath_bar, BREATH_FILL)
    breath_track = _count(breath_bar, BREATH_TRACK)
    print(
        f"   health bar: fill {health_fill:5d} px, track {health_track:5d} px "
        f"(of {health_bar.width * health_bar.height})"
    )
    print(
        f"   breath bar: fill {breath_fill:5d} px, track {breath_track:5d} px "
        f"(of {breath_bar.width * breath_bar.height})"
    )

    # --- death overlay ------------------------------------------------------
    # The dim is a 74% alpha overlay, so the composited colour tracks the world
    # behind it.  What is measurable is the *cast*: red-dominant, low green/blue
    # pixels across the frame, and the title's bright red.
    frame = _rect(image, 0, 0, 1280, 720)
    dim_pixels = 0
    for red, green, blue in frame.get_flattened_data() if hasattr(frame, "get_flattened_data") else frame.getdata():
        if red > 30 and green < 0.62 * red and blue < 0.68 * red and green < 110 and blue < 110:
            dim_pixels += 1
    frame_total = frame.width * frame.height
    dim_share = 100.0 * dim_pixels / frame_total
    title_region = _rect(image, 0, 260, 1280, 400)
    title_pixels = _count(title_region, DEATH_TITLE, tolerance=60)
    print(
        f"   death overlay: red-cast share {dim_share:5.1f}%   bright red title pixels "
        f"{title_pixels} (of {title_region.width * title_region.height})"
    )

    print("   bottom-left vitals map (H = health fill, B = breath fill,"
          " . = dark, # = bright):")
    for line in _vitals_map(image).splitlines():
        print("     " + line)
    print("   whole-frame map (R = red-cast, # = bright, . = dark):")
    for line in _frame_map(image).splitlines():
        print("     " + line)

    ok = True
    if "health" in expectations and health_fill < 200:
        print("   FAIL: no health bar fill found in the expected rectangle")
        ok = False
    if "breath" in expectations and breath_fill < 100:
        print("   FAIL: no breath bar fill found in the expected rectangle")
        ok = False
    if "death" in expectations and (dim_share < 60.0 or title_pixels < 150):
        print("   FAIL: the death overlay does not cover the frame")
        ok = False
    return ok


def main(argv: list[str]) -> int:
    args = [a for a in argv if not a.startswith("--")]
    if not args:
        print(__doc__, file=sys.stderr)
        return 2
    expectations: set[str] = set()
    if "--expect" in argv:
        expectations = set(argv[argv.index("--expect") + 1 :])
    ok = True
    for name in args:
        path = Path(name)
        if not path.is_file():
            print(f"missing: {path}", file=sys.stderr)
            return 2
        ok = probe(path, expectations) and ok
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

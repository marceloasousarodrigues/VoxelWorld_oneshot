"""Generate the M29 medieval architecture textures.

Every texture is drawn procedurally in this repository (no downloaded art), so
the manifest records this script as the source.  Running the script is
idempotent: it rewrites the same PNG bytes and the same manifest entries.

    python godot/tools/generate_m29_textures.py
"""
from __future__ import annotations

import json
import math
import os
import random

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.dirname(HERE)
TEXTURES = os.path.join(GODOT, "assets", "textures")
SOURCES = os.path.join(GODOT, "assets", "texture_sources.json")

SIZE = 128
LICENSE = (
    "M29 procedural texture generated in-repo for VoxelWorld; contains no "
    "third-party art. Free to use and modify with the project (CC BY-SA 3.0 "
    "compatible)."
)
SOURCE = "godot/tools/generate_m29_textures.py"


def _noise(draw: ImageDraw.ImageDraw, colours, count, rng, size=SIZE):
    for _ in range(count):
        x = rng.randrange(size)
        y = rng.randrange(size)
        draw.point((x, y), fill=rng.choice(colours))


# --- masonry and plaster --------------------------------------------------

def plaster() -> Image.Image:
    """Warm lime plaster: soft mottling, faint trowel marks and hairline cracks."""
    image = Image.new("RGBA", (SIZE, SIZE), (211, 201, 178, 255))
    draw = ImageDraw.Draw(image)
    rng = random.Random(2901)
    for _ in range(90):
        x = rng.randrange(-16, SIZE)
        y = rng.randrange(-16, SIZE)
        w = rng.randrange(18, 58)
        h = rng.randrange(12, 38)
        tone = rng.choice([(204, 194, 170, 255), (218, 208, 184, 255),
                           (199, 189, 165, 255), (223, 214, 193, 255)])
        draw.ellipse((x, y, x + w, y + h), fill=tone)
    _noise(draw, [(196, 186, 162, 255), (224, 215, 194, 255), (188, 178, 155, 255)], 4200, rng)
    # Faint trowel arcs and two hairline cracks keep it from reading as flat paint.
    for _ in range(14):
        x = rng.randrange(0, SIZE)
        y = rng.randrange(0, SIZE)
        draw.arc((x - 22, y - 12, x + 22, y + 12), 200, 340, fill=(195, 184, 160, 255), width=1)
    for _ in range(3):
        x = rng.randrange(12, SIZE - 12)
        y = rng.randrange(12, SIZE - 12)
        points = [(x, y)]
        for _step in range(rng.randrange(3, 7)):
            x += rng.randrange(-5, 6)
            y += rng.randrange(4, 10)
            points.append((x, y))
        draw.line(points, fill=(176, 166, 144, 255), width=1)
    return image


def dark_timber() -> Image.Image:
    """Dark structural oak: near-black brown grain with a hand-hewn highlight."""
    image = Image.new("RGBA", (SIZE, SIZE), (74, 49, 33, 255))
    draw = ImageDraw.Draw(image)
    rng = random.Random(2902)
    _noise(draw, [(66, 43, 29, 255), (84, 56, 38, 255), (58, 38, 26, 255)], 3600, rng)
    for x in range(6, SIZE, 14):
        draw.line((x, 0, x + rng.randrange(-2, 3), SIZE), fill=(55, 35, 24, 255), width=2)
        draw.line((x + 3, 0, x + 3 + rng.randrange(-2, 3), SIZE), fill=(96, 64, 44, 255), width=1)
    # Long grain flecks and a couple of knots.
    for _ in range(46):
        x = rng.randrange(2, SIZE - 2)
        y = rng.randrange(2, SIZE - 10)
        draw.line((x, y, x + rng.randrange(-3, 4), y + rng.randrange(5, 20)),
                  fill=rng.choice([(52, 34, 23, 255), (88, 58, 40, 255)]), width=1)
    for _ in range(3):
        x = rng.randrange(18, SIZE - 18)
        y = rng.randrange(18, SIZE - 18)
        draw.ellipse((x - 6, y - 4, x + 6, y + 4), outline=(44, 28, 20, 255), width=2)
        draw.ellipse((x - 2, y - 1, x + 2, y + 1), fill=(40, 26, 18, 255))
    return image


def stone_wall() -> Image.Image:
    """Coursed warm-grey medieval ashlar with lime mortar."""
    image = Image.new("RGBA", (SIZE, SIZE), (150, 145, 133, 255))
    draw = ImageDraw.Draw(image)
    rng = random.Random(2903)
    mortar = (172, 168, 156, 255)
    draw.rectangle((0, 0, SIZE, SIZE), fill=mortar)
    courses = [(0, 22), (23, 46), (47, 70), (71, 94), (95, 118), (119, 128)]
    for index, (top, bottom) in enumerate(courses):
        x = -rng.randrange(8, 26) if index % 2 else -rng.randrange(0, 14)
        while x < SIZE:
            width = rng.randrange(24, 44)
            tone = rng.choice([(146, 141, 129, 255), (157, 151, 138, 255),
                               (137, 132, 121, 255), (164, 158, 145, 255),
                               (128, 124, 114, 255)])
            draw.rectangle((x + 2, top + 2, x + width - 2, bottom - 2), fill=tone)
            draw.line((x + 3, bottom - 3, x + width - 3, bottom - 3), fill=(116, 112, 103, 255), width=1)
            draw.line((x + 3, top + 3, x + width - 3, top + 3), fill=(176, 170, 157, 255), width=1)
            # Pits and a little weathering on each block.
            for _ in range(rng.randrange(5, 14)):
                px = rng.randrange(x + 4, max(x + 5, x + width - 4))
                py = rng.randrange(top + 4, bottom - 4)
                draw.point((px, py), fill=rng.choice([(120, 116, 107, 255), (170, 164, 150, 255)]))
            x += width
    _noise(draw, [(130, 126, 117, 255), (170, 164, 151, 255)], 2400, rng)
    return image


def chimney_side() -> Image.Image:
    """Sooted chimney masonry: smaller stones than the wall, darker near the top."""
    image = stone_wall().copy()
    draw = ImageDraw.Draw(image)
    rng = random.Random(2904)
    for y in range(0, SIZE):
        soot = max(0.0, 1.0 - float(y) / 96.0)
        if soot <= 0.0:
            continue
        for x in range(SIZE):
            if rng.random() < soot * 0.22:
                draw.point((x, y), fill=(76, 72, 66, 255))
    draw.rectangle((0, 0, SIZE, 10), fill=(86, 81, 74, 255))
    draw.line((0, 10, SIZE, 10), fill=(120, 114, 104, 255), width=2)
    return image


def chimney_top() -> Image.Image:
    image = Image.new("RGBA", (SIZE, SIZE), (138, 132, 120, 255))
    draw = ImageDraw.Draw(image)
    rng = random.Random(2905)
    _noise(draw, [(126, 120, 110, 255), (154, 148, 134, 255)], 2600, rng)
    draw.rectangle((0, 0, SIZE - 1, SIZE - 1), outline=(104, 99, 90, 255), width=5)
    draw.ellipse((26, 26, SIZE - 26, SIZE - 26), fill=(62, 58, 53, 255), outline=(96, 90, 82, 255), width=4)
    draw.ellipse((42, 42, SIZE - 42, SIZE - 42), fill=(28, 26, 24, 255))
    return image


def timber_brace() -> Image.Image:
    """Plaster panel inside a dark frame with one diagonal brace."""
    image = plaster().copy()
    draw = ImageDraw.Draw(image)
    dark = (74, 49, 33, 255)
    mid = (96, 64, 42, 255)
    width = 14
    draw.rectangle((0, 0, SIZE - 1, SIZE - 1), outline=dark, width=width)
    draw.line((width, width, SIZE - width, SIZE - width), fill=dark, width=width)
    draw.line((width + 4, width + 4, SIZE - width - 4, SIZE - width - 4), fill=mid, width=3)
    for x, y in ((width // 2, width // 2), (SIZE - width // 2, width // 2),
                 (width // 2, SIZE - width // 2), (SIZE - width // 2, SIZE - width // 2)):
        draw.ellipse((x - 3, y - 3, x + 3, y + 3), fill=(42, 33, 25, 255))
    return image


# --- slate roof -----------------------------------------------------------

def _slate_palette(rng):
    return rng.choice([(94, 93, 92, 255), (86, 85, 84, 255), (100, 99, 98, 255),
                       (80, 79, 78, 255), (104, 103, 102, 255)])


def slate_tile() -> Image.Image:
    """Overlapping warm grey slate shingles with a brown shadow line."""
    image = Image.new("RGBA", (SIZE, SIZE), (90, 89, 88, 255))
    draw = ImageDraw.Draw(image)
    rng = random.Random(2910)
    row_height = 20
    for row_index in range(0, SIZE // row_height + 1):
        top = row_index * row_height
        offset = 0 if row_index % 2 == 0 else 12
        for x in range(-offset, SIZE, 24):
            colour = _slate_palette(rng)
            draw.rounded_rectangle((x + 1, top + 2, x + 23, top + row_height + 8),
                                   radius=4, fill=colour)
            draw.line((x + 3, top + 5, x + 21, top + 5), fill=(132, 132, 130, 255), width=1)
            draw.line((x + 2, top + row_height + 6, x + 22, top + row_height + 6),
                      fill=(56, 56, 58, 255), width=2)
    # Deliberate warm undertone in the gaps so the slate does not read as blue plastic.
    for y in range(0, SIZE, row_height):
        draw.line((0, y + row_height + 7, SIZE, y + row_height + 7), fill=(78, 68, 58, 255), width=1)
    _noise(draw, [(76, 75, 74, 255), (116, 115, 114, 255)], 2600, rng)
    return image


def slate_ridge() -> Image.Image:
    image = slate_tile().copy()
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, SIZE, 20), fill=(96, 95, 94, 255))
    draw.line((0, 4, SIZE, 4), fill=(136, 135, 133, 255), width=3)
    draw.line((0, 20, SIZE, 20), fill=(56, 56, 58, 255), width=3)
    # A row of cap tiles rather than a flat band.
    for x in range(-4, SIZE, 26):
        draw.rounded_rectangle((x + 2, 2, x + 24, 26), radius=6, outline=(58, 58, 60, 255), width=2)
    return image


def slate_side() -> Image.Image:
    """The exposed slate edge and rafter ends under a roof eave."""
    image = Image.new("RGBA", (SIZE, SIZE), (94, 93, 92, 255))
    draw = ImageDraw.Draw(image)
    rng = random.Random(2911)
    _noise(draw, [(84, 83, 82, 255), (118, 117, 116, 255), (74, 73, 72, 255)], 2600, rng)
    for y in range(0, SIZE, 24):
        draw.line((0, y, SIZE, y), fill=(56, 56, 58, 255), width=3)
        draw.line((0, y + 3, SIZE, y + 3), fill=(132, 132, 130, 255), width=1)
    # Under-eave shadow with visible rafter ends instead of a flat black band.
    draw.rectangle((0, SIZE - 30, SIZE, SIZE), fill=(72, 71, 70, 255))
    draw.line((0, SIZE - 30, SIZE, SIZE - 30), fill=(136, 135, 133, 255), width=2)
    for x in range(8, SIZE, 26):
        draw.rectangle((x, SIZE - 26, x + 10, SIZE - 2), fill=(114, 113, 112, 255))
        draw.line((x, SIZE - 26, x, SIZE - 2), fill=(136, 135, 133, 255), width=1)
        draw.line((x + 10, SIZE - 26, x + 10, SIZE - 2), fill=(54, 54, 56, 255), width=1)
    return image


# --- facade details -------------------------------------------------------

def window_texture() -> Image.Image:
    """Dark timber frame, pale glass panes and a central mullion."""
    image = Image.new("RGBA", (SIZE, SIZE), (70, 47, 32, 255))
    draw = ImageDraw.Draw(image)
    rng = random.Random(2920)
    glass = (102, 108, 112, 255)
    draw.rectangle((16, 12, SIZE - 16, SIZE - 12), fill=glass, outline=(48, 34, 24, 255), width=3)
    # Soft sky reflection: a muted grey-blue band across the panes.
    draw.polygon([(24, 20), (56, 20), (24, 70)], fill=(122, 128, 132, 255))
    draw.polygon([(96, 100), (124, 54), (124, 104)], fill=(96, 102, 108, 255))
    # Mullion and transom.
    draw.rectangle((SIZE // 2 - 4, 12, SIZE // 2 + 4, SIZE - 12), fill=(70, 47, 32, 255))
    draw.rectangle((16, SIZE // 2 - 4, SIZE - 16, SIZE // 2 + 4), fill=(70, 47, 32, 255))
    # Outer frame plus a proud sill.
    draw.rectangle((4, 0, SIZE - 5, SIZE - 1), outline=(49, 33, 23, 255), width=8)
    draw.rectangle((0, SIZE - 14, SIZE - 1, SIZE - 1), fill=(60, 40, 27, 255))
    draw.line((0, SIZE - 14, SIZE, SIZE - 14), fill=(112, 76, 50, 255), width=2)
    for _ in range(80):
        x = rng.randrange(22, SIZE - 22)
        y = rng.randrange(18, SIZE - 18)
        if x in range(SIZE // 2 - 4, SIZE // 2 + 5) or y in range(SIZE // 2 - 4, SIZE // 2 + 5):
            continue
        draw.point((x, y), fill=(136, 142, 146, 255))
    return image


def shutter() -> Image.Image:
    """A dark louvered shutter in a sturdy frame."""
    image = Image.new("RGBA", (SIZE, SIZE), (82, 54, 36, 255))
    draw = ImageDraw.Draw(image)
    rng = random.Random(2921)
    _noise(draw, [(72, 47, 31, 255), (94, 62, 42, 255)], 2200, rng)
    draw.rectangle((0, 0, SIZE - 1, SIZE - 1), outline=(48, 32, 22, 255), width=9)
    draw.rectangle((14, 14, SIZE - 15, SIZE - 15), fill=(66, 43, 29, 255))
    for y in range(20, SIZE - 20, 11):
        draw.line((18, y, SIZE - 19, y), fill=(116, 79, 52, 255), width=4)
        draw.line((18, y + 4, SIZE - 19, y + 4), fill=(40, 27, 18, 255), width=2)
    draw.rectangle((SIZE // 2 - 3, 14, SIZE // 2 + 3, SIZE - 15), fill=(48, 32, 22, 255))
    for x, y in ((16, 16), (SIZE - 18, 16), (16, SIZE - 18), (SIZE - 18, SIZE - 18)):
        draw.ellipse((x - 3, y - 3, x + 3, y + 3), fill=(32, 24, 18, 255))
    return image


def finial() -> Image.Image:
    """A small dark-iron ridge finial with a warm brass highlight."""
    image = Image.new("RGBA", (SIZE, SIZE), (54, 56, 58, 255))
    draw = ImageDraw.Draw(image)
    rng = random.Random(2930)
    _noise(draw, [(44, 46, 48, 255), (68, 70, 72, 255)], 2000, rng)
    draw.polygon([(64, 6), (86, 54), (64, 76), (42, 54)], fill=(120, 96, 50, 255),
                 outline=(64, 50, 28, 255))
    draw.polygon([(64, 12), (78, 52), (64, 38)], fill=(178, 146, 80, 255))
    draw.rectangle((58, 76, 70, 112), fill=(60, 62, 64, 255), outline=(34, 36, 38, 255))
    draw.rectangle((46, 110, 82, 122), fill=(46, 48, 50, 255))
    return image


def flower_box() -> Image.Image:
    image = Image.new("RGBA", (SIZE, SIZE), (104, 70, 44, 255))
    draw = ImageDraw.Draw(image)
    rng = random.Random(2940)
    _noise(draw, [(92, 61, 38, 255), (118, 80, 50, 255), (82, 54, 34, 255)], 2400, rng)
    for x in range(6, SIZE, 20):
        draw.line((x, 12, x, SIZE - 12), fill=(66, 44, 29, 255), width=3)
        draw.line((x + 3, 12, x + 3, SIZE - 12), fill=(138, 96, 60, 255), width=1)
    for y in (8, SIZE - 16):
        draw.rectangle((0, y, SIZE, y + 8), fill=(72, 49, 32, 255))
        draw.line((0, y + 2, SIZE, y + 2), fill=(148, 106, 68, 255), width=1)
    return image


def flower_box_bloom() -> Image.Image:
    image = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    rng = random.Random(2941)
    for _ in range(40):
        x = rng.randrange(8, SIZE - 8)
        y = rng.randrange(12, SIZE - 12)
        rx = rng.randrange(5, 11)
        ry = rng.randrange(6, 13)
        colour = rng.choice([(78, 122, 54, 255), (94, 140, 62, 255), (64, 104, 46, 255)])
        draw.ellipse((x - rx, y - ry, x + rx, y + ry), fill=colour,
                     outline=(52, 84, 38, 255))
    petal_colours = [(198, 54, 58, 255), (230, 186, 62, 255), (82, 110, 198, 255),
                     (206, 96, 142, 255)]
    for _ in range(16):
        x = rng.randrange(10, SIZE - 10)
        y = rng.randrange(8, SIZE - 20)
        colour = rng.choice(petal_colours)
        for index in range(5):
            angle = -math.pi / 2 + index * math.tau / 5
            px = x + math.cos(angle) * 6
            py = y + math.sin(angle) * 6
            draw.ellipse((px - 4, py - 4, px + 4, py + 4), fill=colour,
                         outline=tuple(max(0, value - 34) for value in colour[:3]) + (255,))
        draw.ellipse((x - 2, y - 2, x + 2, y + 2), fill=(244, 212, 96, 255))
    return image


TEXTURES_TO_WRITE = {
    "plaster": (plaster(), "warm lime-plaster infill", 4),
    "dark_timber": (dark_timber(), "dark structural oak", 4),
    "stone_wall": (stone_wall(), "coursed warm-grey medieval stone", 4),
    "timber_brace": (timber_brace(), "plaster panel with a diagonal dark brace", 4),
    "slate_tile": (slate_tile(), "grey-blue slate shingles", 4),
    "slate_ridge": (slate_ridge(), "slate ridge cap with warm shadow", 4),
    "slate_side": (slate_side(), "exposed slate roof edge and eave underside", 4),
    "window": (window_texture(), "framed window with glass and mullion", 4),
    "shutter": (shutter(), "louvered timber shutter", 4),
    "chimney_side": (chimney_side(), "sooted chimney masonry", 4),
    "chimney_top": (chimney_top(), "chimney cap with a dark flue", 4),
    "finial": (finial(), "dark iron ridge finial", 4),
    "flower_box": (flower_box(), "wooden flower-box planter", 4),
    "flower_box_bloom": (flower_box_bloom(), "flower-box leaves and blooms", 4),
}


def main() -> None:
    os.makedirs(TEXTURES, exist_ok=True)
    with open(SOURCES, "r", encoding="utf-8") as handle:
        manifest = json.load(handle)
    for key, (image, description, frames) in TEXTURES_TO_WRITE.items():
        file_name = f"m29_{key}.png"
        image.save(os.path.join(TEXTURES, file_name))
        manifest["textures"][key] = {
            "description": description,
            "file": file_name,
            "height": image.height,
            "key": key,
            "license": LICENSE,
            "source": SOURCE,
            "width": image.width,
        }
    with open(SOURCES, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=2)
        handle.write("\n")
    print(f"wrote {len(TEXTURES_TO_WRITE)} M29 textures and manifest entries")


if __name__ == "__main__":
    main()

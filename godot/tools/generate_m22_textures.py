"""Generate the M22 vegetation and medieval-architecture textures.

All textures are drawn procedurally in this repository (no downloaded art), so
the manifest records this script as the source.  Running the script is
idempotent: it rewrites the same PNG bytes and the same manifest entries.

    python godot/tools/generate_m22_textures.py
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
    "M22 procedural texture generated in-repo for VoxelWorld; contains no "
    "third-party art. Free to use and modify with the project (CC BY-SA 3.0 "
    "compatible)."
)
SOURCE = "godot/tools/generate_m22_textures.py"


def _noise(draw: ImageDraw.ImageDraw, colours, count, rng, size=SIZE):
    for _ in range(count):
        x = rng.randrange(size)
        y = rng.randrange(size)
        draw.point((x, y), fill=rng.choice(colours))


def _leaf_blob(draw, cx, cy, rx, ry, colour, outline, rng, veins=None):
    draw.ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=colour, outline=outline)
    if veins and rx > 5:
        draw.line((cx, cy - ry + 2, cx, cy + ry - 2), fill=veins, width=1)
        for step in (-ry // 2, 0, ry // 2):
            draw.line((cx, cy + step, cx - rx + 2, cy + step - 3), fill=veins, width=1)
            draw.line((cx, cy + step, cx + rx - 2, cy + step - 3), fill=veins, width=1)


# --- wood -----------------------------------------------------------------

def birch_log_side() -> Image.Image:
    image = Image.new("RGBA", (SIZE, SIZE), (214, 208, 188, 255))
    draw = ImageDraw.Draw(image)
    rng = random.Random(3201)
    _noise(draw, [(206, 199, 177, 255), (224, 219, 202, 255), (196, 190, 170, 255)], 2600, rng)
    for _ in range(26):
        x = rng.randrange(4, SIZE - 4)
        y = rng.randrange(2, SIZE - 6)
        length = rng.randrange(5, 18)
        draw.line((x, y, x, min(SIZE - 1, y + length)), fill=(62, 56, 48, 255), width=rng.choice([2, 2, 3]))
    for _ in range(14):
        x = rng.randrange(2, SIZE - 10)
        y = rng.randrange(2, SIZE - 2)
        draw.line((x, y, x + rng.randrange(4, 12), y), fill=(96, 88, 74, 255), width=1)
    return image


def birch_log_top() -> Image.Image:
    image = Image.new("RGBA", (SIZE, SIZE), (196, 188, 166, 255))
    draw = ImageDraw.Draw(image)
    rng = random.Random(3202)
    _noise(draw, [(184, 176, 154, 255), (208, 200, 178, 255)], 1400, rng)
    for radius in range(8, 62, 8):
        shade = (150, 138, 112, 255) if radius % 16 == 0 else (174, 162, 136, 255)
        draw.ellipse((SIZE // 2 - radius, SIZE // 2 - radius, SIZE // 2 + radius, SIZE // 2 + radius),
                     outline=shade, width=2)
    draw.ellipse((SIZE // 2 - 5, SIZE // 2 - 5, SIZE // 2 + 5, SIZE // 2 + 5), fill=(122, 106, 78, 255))
    return image


def timber_frame() -> Image.Image:
    image = Image.new("RGBA", (SIZE, SIZE), (166, 124, 82, 255))
    draw = ImageDraw.Draw(image)
    rng = random.Random(3210)
    _noise(draw, [(152, 112, 74, 255), (178, 136, 92, 255), (140, 102, 66, 255)], 2400, rng)
    # Vertical plank seams on the infill.
    for x in range(16, SIZE, 24):
        draw.line((x, 0, x, SIZE), fill=(128, 92, 58, 255), width=2)
        draw.line((x + 2, 0, x + 2, SIZE), fill=(188, 146, 100, 255), width=1)
    # Dark structural frame: border plus a diagonal brace.
    dark = (82, 54, 36, 255)
    mid = (106, 72, 46, 255)
    width = 13
    draw.rectangle((0, 0, SIZE - 1, SIZE - 1), outline=dark, width=width)
    draw.line((width, width, SIZE - width, SIZE - width), fill=dark, width=width)
    draw.line((width + 4, width + 4, SIZE - width - 4, SIZE - width - 4), fill=mid, width=3)
    # Small nail heads give the frame a hand-built read.
    for x, y in ((width // 2, width // 2), (SIZE - width // 2, width // 2),
                 (width // 2, SIZE - width // 2), (SIZE - width // 2, SIZE - width // 2)):
        draw.ellipse((x - 2, y - 2, x + 2, y + 2), fill=(48, 46, 44, 255))
    return image


def planks_door() -> Image.Image:
    image = Image.new("RGBA", (SIZE, SIZE), (150, 108, 70, 255))
    draw = ImageDraw.Draw(image)
    rng = random.Random(3211)
    _noise(draw, [(136, 96, 62, 255), (164, 120, 80, 255), (126, 88, 56, 255)], 2200, rng)
    for x in range(8, SIZE, 26):
        draw.line((x, 0, x, SIZE), fill=(88, 60, 38, 255), width=3)
        draw.line((x + 3, 0, x + 3, SIZE), fill=(178, 132, 88, 255), width=1)
    # Iron hinges and a bright ring handle.
    draw.rectangle((0, 26, 38, 34), fill=(56, 54, 52, 255))
    draw.rectangle((0, 92, 38, 100), fill=(56, 54, 52, 255))
    draw.ellipse((84, 58, 106, 80), outline=(50, 48, 46, 255), width=5)
    draw.ellipse((88, 62, 102, 76), outline=(206, 164, 92, 255), width=3)
    return image


# --- foliage --------------------------------------------------------------

def _leafy(size: int, palette, seed: int, coverage: float, blossom=None) -> Image.Image:
    image = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    rng = random.Random(seed)
    count = int(76 * coverage)
    for _ in range(count):
        x = rng.randrange(6, SIZE - 6)
        y = rng.randrange(4, SIZE - 6)
        rx = rng.randrange(4, 10)
        ry = rng.randrange(5, 11)
        colour = rng.choice(palette)
        outline = tuple(max(0, channel - 26) for channel in colour[:3]) + (255,)
        _leaf_blob(draw, x, y, rx, ry, colour, outline, rng)
    if blossom:
        for _ in range(18):
            x = rng.randrange(8, SIZE - 8)
            y = rng.randrange(6, SIZE - 6)
            r = rng.randrange(3, 6)
            draw.ellipse((x - r, y - r, x + r, y + r), fill=blossom)
            draw.ellipse((x - 1, y - 1, x + 1, y + 1), fill=(236, 208, 160, 255))
    return image


def birch_leaves() -> Image.Image:
    return _leafy(SIZE, [(112, 154, 76, 255), (134, 174, 92, 255), (96, 136, 66, 255),
                         (152, 188, 104, 255)], 3220, 1.0)


def blossom_leaves() -> Image.Image:
    return _leafy(SIZE, [(118, 150, 84, 255), (140, 166, 94, 255), (102, 134, 72, 255)],
                  3221, 0.95, blossom=(232, 166, 196, 255))


def bush() -> Image.Image:
    image = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    rng = random.Random(3230)
    for _ in range(120):
        cx = SIZE // 2 + rng.randint(-46, 46)
        cy = SIZE // 2 + rng.randint(-58, 34)
        rx = rng.randint(6, 15)
        ry = rng.randint(7, 16)
        colour = rng.choice([(66, 112, 46, 255), (82, 130, 56, 255), (52, 94, 38, 255),
                             (96, 142, 62, 255)])
        outline = tuple(max(0, value - 24) for value in colour[:3]) + (255,)
        draw.ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=colour, outline=outline)
    for _ in range(8):
        x = rng.randint(28, 98)
        y = rng.randint(44, 104)
        draw.ellipse((x, y, x + 7, y + 7), fill=(186, 58, 58, 255))
        draw.point((x + 2, y + 2), fill=(238, 130, 120, 255))
    return image


# --- flowers --------------------------------------------------------------

def flower(petal, centre, seed) -> Image.Image:
    image = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    rng = random.Random(seed)
    stem = (78, 120, 54, 255)
    # Deliberately low in the tile: the mesher anchors decoration at the bottom.
    base_y = SIZE - 8
    top_y = 30
    draw.line((SIZE // 2, base_y, SIZE // 2 + rng.randint(-3, 3), top_y + 18), fill=stem, width=5)
    for side in (-1, 1):
        y = base_y - rng.randint(28, 54)
        draw.line((SIZE // 2, y, SIZE // 2 + side * 20, y - 16), fill=stem, width=3)
        draw.ellipse((SIZE // 2 + side * 20 - 9, y - 24, SIZE // 2 + side * 20 + 7, y - 10),
                     fill=(92, 140, 62, 255))
    cx = SIZE // 2 + rng.randint(-4, 4)
    cy = top_y
    for index in range(7):
        angle = -math.pi / 2 + index * math.tau / 7
        px = cx + math.cos(angle) * 15
        py = cy + math.sin(angle) * 15
        draw.ellipse((px - 10, py - 8, px + 10, py + 8), fill=petal,
                     outline=tuple(max(0, value - 40) for value in petal[:3]) + (255,))
    draw.ellipse((cx - 7, cy - 7, cx + 7, cy + 7), fill=centre)
    return image


# --- architecture ---------------------------------------------------------

def roof_tile() -> Image.Image:
    image = Image.new("RGBA", (SIZE, SIZE), (142, 78, 54, 255))
    draw = ImageDraw.Draw(image)
    rng = random.Random(3240)
    _noise(draw, [(132, 72, 50, 255), (156, 88, 60, 255), (122, 66, 46, 255)], 2200, rng)
    row_height = 22
    for row in range(0, SIZE + row_height, row_height):
        draw.rectangle((0, row, SIZE, row + row_height - 3), outline=(92, 48, 34, 255), width=2)
        offset = 0 if (row // row_height) % 2 == 0 else row_height
        for x in range(-offset, SIZE, row_height * 2):
            draw.arc((x, row - 2, x + row_height * 2, row + row_height + 4), 185, 355,
                     fill=(166, 96, 66, 255), width=2)
            draw.line((x + row_height, row + 3, x + row_height, row + row_height - 4),
                      fill=(104, 54, 38, 255), width=2)
    draw.line((0, 0, SIZE, 0), fill=(178, 106, 74, 255), width=3)
    return image


def roof_ridge() -> Image.Image:
    image = roof_tile().copy()
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, SIZE, 18), fill=(92, 48, 36, 255))
    draw.line((0, 3, SIZE, 3), fill=(170, 96, 66, 255), width=3)
    draw.line((0, 18, SIZE, 18), fill=(68, 36, 28, 255), width=2)
    return image


def roof_side() -> Image.Image:
    """The vertical face of a roof step: tile courses above a shadowed eave."""
    image = Image.new("RGBA", (SIZE, SIZE), (146, 84, 58, 255))
    draw = ImageDraw.Draw(image)
    rng = random.Random(3245)
    _noise(draw, [(132, 76, 52, 255), (160, 94, 66, 255), (120, 70, 48, 255)], 1800, rng)
    for row in range(0, 88, 26):
        draw.line((0, row, SIZE, row), fill=(104, 58, 40, 255), width=3)
        draw.line((0, row + 3, SIZE, row + 3), fill=(178, 104, 72, 255), width=1)
        offset = 0 if (row // 26) % 2 == 0 else 14
        for x in range(offset, SIZE, 28):
            draw.line((x, row + 4, x, row + 25), fill=(114, 64, 44, 255), width=2)
    # Shadowed under-eave band with exposed rafter ends.
    draw.rectangle((0, 88, SIZE, SIZE), fill=(76, 46, 34, 255))
    draw.line((0, 88, SIZE, 88), fill=(164, 96, 68, 255), width=3)
    for x in range(10, SIZE, 32):
        draw.rectangle((x, 100, x + 8, SIZE - 2), fill=(94, 58, 42, 255))
    return image


def path_top() -> Image.Image:
    image = Image.new("RGBA", (SIZE, SIZE), (112, 94, 70, 255))
    draw = ImageDraw.Draw(image)
    rng = random.Random(3250)
    _noise(draw, [(100, 84, 62, 255), (126, 106, 78, 255), (90, 74, 56, 255)], 2800, rng)
    for _ in range(30):
        x = rng.randrange(4, SIZE - 8)
        y = rng.randrange(4, SIZE - 8)
        r = rng.randrange(3, 7)
        shade = rng.choice([(108, 100, 86, 255), (92, 86, 74, 255), (130, 120, 102, 255)])
        draw.ellipse((x, y, x + r * 2, y + r), fill=shade, outline=(76, 68, 56, 255))
    return image


def path_side() -> Image.Image:
    image = Image.new("RGBA", (SIZE, SIZE), (104, 82, 58, 255))
    draw = ImageDraw.Draw(image)
    rng = random.Random(3251)
    _noise(draw, [(92, 72, 50, 255), (118, 94, 66, 255), (82, 64, 44, 255)], 2500, rng)
    draw.rectangle((0, 0, SIZE, 12), fill=(136, 116, 88, 255))
    for x in range(0, SIZE, 20):
        draw.line((x, 0, x + rng.randint(-4, 4), 12), fill=(108, 90, 66, 255), width=2)
    return image


def lantern_side() -> Image.Image:
    image = Image.new("RGBA", (SIZE, SIZE), (44, 42, 42, 255))
    draw = ImageDraw.Draw(image)
    # Iron frame with four warm panes.
    draw.rectangle((8, 8, SIZE - 8, SIZE - 8), fill=(58, 48, 38, 255), outline=(28, 26, 26, 255), width=5)
    for x in (16, SIZE // 2 + 2):
        for y in (16, SIZE // 2 + 2):
            draw.rectangle((x, y, x + SIZE // 2 - 22, y + SIZE // 2 - 22),
                           fill=(226, 142, 58, 255), outline=(44, 36, 30, 255), width=4)
            draw.rectangle((x + 7, y + 7, x + 16, y + 16), fill=(255, 206, 120, 255))
    draw.line((SIZE // 2 - 3, 0, SIZE // 2 - 3, SIZE), fill=(34, 32, 30, 255), width=6)
    draw.line((0, SIZE // 2 - 3, SIZE, SIZE // 2 - 3), fill=(34, 32, 30, 255), width=6)
    draw.rectangle((0, 0, SIZE - 1, 7), fill=(40, 38, 36, 255))
    return image


def lantern_top() -> Image.Image:
    image = Image.new("RGBA", (SIZE, SIZE), (46, 44, 42, 255))
    draw = ImageDraw.Draw(image)
    draw.ellipse((18, 18, SIZE - 18, SIZE - 18), fill=(62, 56, 48, 255), outline=(30, 28, 26, 255), width=5)
    draw.ellipse((46, 46, SIZE - 46, SIZE - 46), fill=(210, 132, 52, 255))
    return image


def fence_wood() -> Image.Image:
    image = Image.new("RGBA", (SIZE, SIZE), (124, 88, 56, 255))
    draw = ImageDraw.Draw(image)
    rng = random.Random(3260)
    _noise(draw, [(112, 78, 48, 255), (136, 98, 62, 255), (102, 70, 44, 255)], 2200, rng)
    for y in (22, 74):
        draw.rectangle((0, y, SIZE, y + 20), fill=(138, 99, 62, 255), outline=(80, 54, 34, 255), width=2)
        draw.line((0, y + 4, SIZE, y + 4), fill=(166, 122, 78, 255), width=2)
    return image


def barrel_side() -> Image.Image:
    image = Image.new("RGBA", (SIZE, SIZE), (122, 84, 52, 255))
    draw = ImageDraw.Draw(image)
    rng = random.Random(3270)
    _noise(draw, [(110, 74, 46, 255), (136, 94, 58, 255), (98, 66, 42, 255)], 2400, rng)
    for x in range(6, SIZE, 22):
        draw.line((x, 0, x, SIZE), fill=(76, 52, 34, 255), width=3)
        draw.line((x + 3, 0, x + 3, SIZE), fill=(150, 106, 66, 255), width=1)
    for y in (20, SIZE - 32):
        draw.rectangle((0, y, SIZE, y + 12), fill=(62, 60, 56, 255))
        draw.line((0, y + 3, SIZE, y + 3), fill=(104, 102, 96, 255), width=2)
    return image


def barrel_top() -> Image.Image:
    image = Image.new("RGBA", (SIZE, SIZE), (104, 74, 48, 255))
    draw = ImageDraw.Draw(image)
    rng = random.Random(3271)
    _noise(draw, [(94, 66, 44, 255), (116, 84, 54, 255), (84, 58, 38, 255)], 1600, rng)
    for x in range(0, SIZE, 18):
        draw.line((x, 0, x, SIZE), fill=(86, 60, 40, 255), width=3)
    # One iron rim and a single central bung: a lid, not a target.
    draw.ellipse((14, 14, SIZE - 14, SIZE - 14), outline=(70, 50, 34, 255), width=4)
    draw.ellipse((22, 22, SIZE - 22, SIZE - 22), outline=(126, 92, 60, 255), width=2)
    draw.ellipse((SIZE // 2 - 8, SIZE // 2 - 8, SIZE // 2 + 8, SIZE // 2 + 8),
                 fill=(58, 50, 44, 255), outline=(146, 110, 72, 255), width=2)
    return image


TEXTURES_TO_WRITE = {
    "birch_log_side": (birch_log_side(), "birch log side (pale bark)", 3),
    "birch_log_top": (birch_log_top(), "birch log top (growth rings)", 3),
    "birch_leaves_clean": (birch_leaves(), "birch leaves (light, airy canopy)", 3),
    "blossom_leaves_clean": (blossom_leaves(), "blossom leaves (pink accent canopy)", 3),
    "deco_bush": (bush(), "bush decoration (crossed quads)", 3),
    "deco_flower_red": (flower((196, 54, 58, 255), (242, 196, 84, 255), 3280), "red wildflower", 3),
    "deco_flower_yellow": (flower((232, 190, 62, 255), (214, 132, 44, 255), 3281), "yellow wildflower", 3),
    "deco_flower_blue": (flower((86, 116, 202, 255), (236, 224, 150, 255), 3282), "blue wildflower", 3),
    "timber_frame": (timber_frame(), "timber-framed wall (dark beams over planks)", 3),
    "roof_tile": (roof_tile(), "terracotta roof tiles", 3),
    "roof_ridge": (roof_ridge(), "roof ridge cap", 3),
    "roof_side": (roof_side(), "roof eave/edge face", 3),
    "path_top": (path_top(), "packed path top (earth and pebbles)", 3),
    "path_side": (path_side(), "packed path side", 3),
    "lantern_side": (lantern_side(), "lantern iron frame and warm pane", 3),
    "lantern_top": (lantern_top(), "lantern iron cap", 3),
    "fence": (fence_wood(), "fence rail timber", 3),
    "barrel_side": (barrel_side(), "barrel staves and iron bands", 3),
    "barrel_top": (barrel_top(), "barrel lid", 3),
    "door": (planks_door(), "plank door with iron hinges", 3),
}


def main() -> None:
    os.makedirs(TEXTURES, exist_ok=True)
    with open(SOURCES, "r", encoding="utf-8") as handle:
        manifest = json.load(handle)
    for key, (image, description, frames) in TEXTURES_TO_WRITE.items():
        file_name = f"m22_{key}.png"
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
    print(f"wrote {len(TEXTURES_TO_WRITE)} M22 textures and manifest entries")


if __name__ == "__main__":
    main()

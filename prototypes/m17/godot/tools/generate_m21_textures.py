"""Generate the M21 farming/storage textures and their manifest entries.

The textures are small procedural pixel art drawn in-repo (no external asset is
downloaded), so the manifest records this script as the source.  Running the
script is idempotent: it rewrites the same PNG bytes and the same manifest
entries.

    python prototypes/m17/godot/tools/generate_m21_textures.py
"""
from __future__ import annotations

import json
import os
import random
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.dirname(HERE)
TEXTURES = os.path.join(GODOT, "assets", "textures")
SOURCES = os.path.join(GODOT, "assets", "texture_sources.json")

SIZE = 64
LICENSE = (
    "M21 procedural texture generated in-repo for VoxelWorld; contains no "
    "third-party art. Free to use and modify with the project (CC BY-SA 3.0 "
    "compatible)."
)
SOURCE = "prototypes/m17/godot/tools/generate_m21_textures.py"


def _noise(draw: ImageDraw.ImageDraw, box, colours, count, rng):
    x0, y0, x1, y1 = box
    for _ in range(count):
        x = rng.randint(x0, x1 - 1)
        y = rng.randint(y0, y1 - 1)
        draw.point((x, y), fill=rng.choice(colours))


def farmland_top() -> Image.Image:
    image = Image.new("RGBA", (SIZE, SIZE), (110, 76, 46, 255))
    draw = ImageDraw.Draw(image)
    rng = random.Random(2101)
    _noise(draw, (0, 0, SIZE, SIZE), [(96, 66, 40, 255), (126, 88, 54, 255)], 900, rng)
    for row in range(3, SIZE, 12):
        draw.line([(0, row), (SIZE, row)], fill=(78, 52, 31, 255), width=2)
        draw.line([(0, row + 3), (SIZE, row + 3)], fill=(132, 94, 58, 255), width=1)
    return image


def farmland_side() -> Image.Image:
    image = Image.new("RGBA", (SIZE, SIZE), (104, 72, 44, 255))
    draw = ImageDraw.Draw(image)
    rng = random.Random(2102)
    _noise(draw, (0, 0, SIZE, SIZE), [(90, 61, 37, 255), (120, 84, 52, 255)], 1100, rng)
    draw.rectangle((0, 0, SIZE, 10), fill=(78, 52, 31, 255))
    for col in range(0, SIZE, 8):
        draw.line([(col, 0), (col, 10)], fill=(64, 42, 25, 255), width=2)
    return image


def wheat_stage(stage: int) -> Image.Image:
    image = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    rng = random.Random(2200 + stage)
    green = [(74, 128, 44, 255), (92, 150, 56, 255), (60, 108, 38, 255)]
    gold = [(196, 166, 62, 255), (224, 194, 84, 255)]
    stalks = 3 + stage * 2
    bottom = SIZE - 2
    top = bottom - (14 + stage * 13)
    for index in range(stalks):
        x = 8 + index * (int((SIZE - 16) / max(1, stalks - 1)))
        x += rng.randint(-1, 1)
        height = top + rng.randint(-3, 3)
        colour = green[0] if stage < 3 else gold[0]
        draw.line([(x, bottom), (x, height)], fill=colour, width=2)
        # A leaf pair and, when ripe, a grain head.
        draw.line([(x, height + 8), (x - 4, height + 2)], fill=green[1], width=1)
        draw.line([(x, height + 12), (x + 4, height + 6)], fill=green[2], width=1)
        if stage >= 1:
            draw.line([(x, height), (x - 3, height - 4)], fill=green[1], width=1)
        if stage >= 3:
            for offset in range(0, 9, 2):
                draw.line([(x - 4, height + offset), (x + 4, height + offset)], fill=gold[1], width=1)
    return image


def _round_blob(size, colour, highlight) -> Image.Image:
    image = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    box = ((SIZE - size) // 2, (SIZE - size) // 2 + 4, (SIZE + size) // 2, (SIZE + size) // 2 + 4)
    draw.ellipse(box, fill=colour)
    draw.ellipse((box[0] + 6, box[1] + 4, box[0] + 18, box[1] + 14), fill=highlight)
    return image


def _star_points(cx, cy, outer, inner, count=5):
    import math

    points = []
    for index in range(count * 2):
        radius = outer if index % 2 == 0 else inner
        angle = -math.pi / 2 + index * math.pi / count
        points.append((cx + math.cos(angle) * radius, cy + math.sin(angle) * radius))
    return points


def bone() -> Image.Image:
    image = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    white = (236, 232, 218, 255)
    shade = (206, 200, 184, 255)
    draw.rectangle((22, 26, 42, 38), fill=white)
    for cx in (18, 46):
        for cy in (22, 42):
            draw.ellipse((cx - 7, cy - 7, cx + 7, cy + 7), fill=white)
    draw.line([(22, 34), (42, 34)], fill=shade, width=2)
    return image


def seeds() -> Image.Image:
    image = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    rng = random.Random(2501)
    for _ in range(14):
        x = rng.randint(14, 46)
        y = rng.randint(16, 46)
        draw.ellipse((x, y, x + 6, y + 9), fill=(190, 158, 78, 255),
                     outline=(150, 120, 54, 255))
    return image


def bone_meal() -> Image.Image:
    image = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    rng = random.Random(2502)
    for _ in range(90):
        x = rng.randint(14, 48)
        y = rng.randint(24, 46)
        shade = rng.choice([(238, 236, 226, 255), (220, 216, 202, 255), (250, 248, 240, 255)])
        draw.ellipse((x, y, x + 3, y + 3), fill=shade)
    return image


TEXTURES_TO_WRITE = {
    "farmland_top": (farmland_top(), "farmland top (tilled soil)", 3),
    "farmland_side": (farmland_side(), "farmland side (tilled soil)", 3),
    "wheat_stage_0": (wheat_stage(0), "wheat crop stage 0 (sprout)", 3),
    "wheat_stage_1": (wheat_stage(1), "wheat crop stage 1", 3),
    "wheat_stage_2": (wheat_stage(2), "wheat crop stage 2", 3),
    "wheat_stage_3": (wheat_stage(3), "wheat crop stage 3 (ripe)", 3),
    "item_raw_meat": (_round_blob(34, (178, 66, 58, 255), (214, 108, 96, 255)), "raw meat icon", 4),
    "item_cooked_meat": (_round_blob(34, (140, 84, 44, 255), (190, 128, 74, 255)), "cooked meat icon", 4),
    "item_hide": (_round_blob(36, (168, 126, 78, 255), (206, 168, 116, 255)), "hide icon", 4),
    "item_bone": (bone(), "bone icon", 4),
    "item_wheat_seeds": (seeds(), "wheat seeds icon", 4),
    "item_bone_meal": (bone_meal(), "bone meal icon", 4),
}


def main() -> None:
    os.makedirs(TEXTURES, exist_ok=True)
    with open(SOURCES, "r", encoding="utf-8") as handle:
        manifest = json.load(handle)
    for key, (image, description, frames) in TEXTURES_TO_WRITE.items():
        file_name = f"m21_{key}.png"
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
    print(f"wrote {len(TEXTURES_TO_WRITE)} M21 textures and manifest entries")


if __name__ == "__main__":
    main()

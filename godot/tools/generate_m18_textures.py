"""Generate the M18 station textures from the vendored Minetest art.

The derived PNGs are written next to the originals and are recorded in
`assets/texture_sources.json` as M18 derivatives.  The source pack is the same
Minetest default texture pack already used by the project (CC BY-SA 3.0); this
script only adds contrast, framing and station-specific details.

Run from the repository root:
    python godot/tools/generate_m18_textures.py
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

GODOT = Path(__file__).resolve().parents[1]
TEXTURES = GODOT / "assets" / "textures"
SIZE = 128


def load(name: str) -> Image.Image:
    return Image.open(TEXTURES / name).convert("RGBA")


def grade(image: Image.Image, saturation: float = 0.9, brightness: float = 0.96) -> Image.Image:
    image = ImageEnhance.Color(image).enhance(saturation)
    return ImageEnhance.Brightness(image).enhance(brightness)


def crafting_table_top() -> None:
    base = grade(load("default_wood.png"), 0.82, 0.94)
    draw = ImageDraw.Draw(base)
    # Raised outer frame drawn as an outline so the plank grain remains visible.
    draw.rectangle((0, 0, SIZE - 1, SIZE - 1), outline=(70, 44, 25, 255), width=8)
    draw.rectangle((8, 8, SIZE - 9, SIZE - 9), outline=(196, 145, 86, 255), width=3)
    draw.rectangle((11, 11, SIZE - 12, SIZE - 12), outline=(116, 76, 40, 255), width=2)
    # 3x3 working grid, inset into the top.
    left, top, right, bottom = 17, 17, SIZE - 18, SIZE - 18
    for i in (1, 2):
        x = left + (right - left) * i // 3
        y = top + (bottom - top) * i // 3
        draw.rectangle((x - 1, top, x + 1, bottom), fill=(72, 45, 25, 255))
        draw.rectangle((left, y - 1, right, y + 1), fill=(72, 45, 25, 255))
        draw.line((x + 2, top, x + 2, bottom), fill=(226, 178, 112, 255), width=1)
        draw.line((left, y + 2, right, y + 2), fill=(226, 178, 112, 255), width=1)
    # Corner brackets make the tabletop read as a built object.
    bracket = (92, 57, 30, 255)
    for x, y, dx, dy in (
        (13, 13, 1, 1),
        (SIZE - 14, 13, -1, 1),
        (13, SIZE - 14, 1, -1),
        (SIZE - 14, SIZE - 14, -1, -1),
    ):
        draw.line((x, y, x + 12 * dx, y), fill=bracket, width=3)
        draw.line((x, y, x, y + 12 * dy), fill=bracket, width=3)
    base.save(TEXTURES / "crafting_table_top.png")


def crafting_table_side() -> None:
    base = grade(load("default_wood.png"), 0.84, 0.93)
    draw = ImageDraw.Draw(base)
    # A darker recessed rail with two metal bolts.
    draw.rectangle((10, 74, SIZE - 11, 106), fill=(92, 57, 30, 255))
    draw.rectangle((12, 76, SIZE - 13, 82), fill=(164, 111, 62, 255))
    draw.rectangle((12, 98, SIZE - 13, 104), fill=(72, 45, 25, 255))
    for x in (26, SIZE - 27):
        draw.ellipse((x - 4, 86, x + 4, 94), fill=(196, 170, 104, 255))
        draw.ellipse((x - 2, 88, x + 2, 92), fill=(112, 84, 44, 255))
    # A simple hanging saw silhouette: wooden handle and steel blade.
    draw.rounded_rectangle((20, 22, 42, 58), radius=6, fill=(92, 57, 30, 255))
    draw.polygon(((44, 30), (104, 36), (104, 48), (44, 54)), fill=(156, 164, 168, 255))
    for x in range(48, 104, 8):
        draw.polygon(((x, 48), (x + 4, 56), (x + 8, 48)), fill=(156, 164, 168, 255))
    base.save(TEXTURES / "crafting_table_side.png")


def furnace_opening() -> None:
    # A recessed dark interior with warm embers at the base.
    image = Image.new("RGBA", (SIZE, SIZE), (28, 24, 22, 255))
    draw = ImageDraw.Draw(image)
    # Sooty inner walls: dark at the top, warmer toward the hearth.
    for y in range(SIZE):
        shade = 22 + int(18 * (y / SIZE))
        draw.line((0, y, SIZE, y), fill=(shade + 4, shade, shade - 2, 255))
    draw.rectangle((4, 4, SIZE - 5, SIZE - 5), outline=(52, 45, 40, 255), width=3)
    # Glowing hearth at the bottom.
    for i in range(12):
        y = 90 + i * 2
        shade = max(30, 120 - i * 7)
        draw.rectangle((24, y, SIZE - 25, y + 1), fill=(shade, max(12, shade // 3), 8, 255))
    glow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(glow)
    gdraw.ellipse((18, 70, SIZE - 19, SIZE - 8), fill=(255, 112, 24, 190))
    gdraw.ellipse((32, 90, SIZE - 33, SIZE - 12), fill=(255, 198, 74, 220))
    image = Image.alpha_composite(image, glow.filter(ImageFilter.GaussianBlur(7)))
    # A few bright coals.
    draw = ImageDraw.Draw(image)
    for x, y, w, h in ((38, 106, 12, 5), (58, 100, 16, 6), (82, 108, 11, 4), (69, 94, 8, 4)):
        draw.rectangle((x, y, x + w, y + h), fill=(255, 214, 106, 255))
    image.save(TEXTURES / "furnace_opening.png")


def dense_leaves(source: str, output: str, tint: tuple, fill: int) -> None:
    """Fill most transparent holes so a canopy reads as a green mass.

    The original Minetest leaf art is a thin scatter of pixels; at one tile per
    metre that makes tree crowns look like floating confetti and shimmers when
    the camera moves.  Keeping a minority of holes preserves the cutout look.
    """
    image = load(source)
    pixels = image.load()
    total = [0, 0, 0, 0]
    opaque = 0
    for y in range(SIZE):
        for x in range(SIZE):
            r, g, b, a = pixels[x, y]
            if a > 120:
                total[0] += r
                total[1] += g
                total[2] += b
                opaque += 1
    if opaque:
        base = (total[0] // opaque, total[1] // opaque, total[2] // opaque)
    else:
        base = (60, 120, 60)
    base = (
        min(255, int(base[0] * tint[0])),
        min(255, int(base[1] * tint[1])),
        min(255, int(base[2] * tint[2])),
    )
    for y in range(SIZE):
        for x in range(SIZE):
            r, g, b, a = pixels[x, y]
            if a <= 120:
                hashed = (x * 374761393 + y * 668265263) & 0x7FFFFFFF
                if fill > 0 and hashed % 100 < fill:
                    pixels[x, y] = (0, 0, 0, 0)
                    continue
                shade = 72 + hashed % 44
                pixels[x, y] = (
                    min(255, base[0] * shade // 100),
                    min(255, base[1] * shade // 100),
                    min(255, base[2] * shade // 100),
                    255,
                )
            else:
                pixels[x, y] = (r, g, b, 255)
    image.save(TEXTURES / output)


def glass_clean() -> None:
    image = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, SIZE - 1, SIZE - 1), fill=(124, 176, 196, 54))
    draw.rectangle((2, 2, SIZE - 3, SIZE - 3), outline=(196, 228, 238, 225), width=4)
    draw.rectangle((8, 8, SIZE - 9, SIZE - 9), outline=(236, 248, 252, 120), width=2)
    draw.polygon(((18, 112), (112, 18), (138, 26), (44, 120)), fill=(232, 248, 255, 70))
    draw.line((10, 120, 120, 10), fill=(240, 252, 255, 150), width=3)
    image.save(TEXTURES / "glass_clean.png")


def main() -> None:
    crafting_table_top()
    crafting_table_side()
    furnace_opening()
    glass_clean()
    dense_leaves("default_leaves.png", "oak_leaves_clean.png", (1.0, 1.02, 0.96), 28)
    dense_leaves("default_pine_needles.png", "pine_leaves_clean.png", (0.88, 1.02, 0.92), 24)
    print("wrote crafting_table_top.png, crafting_table_side.png, furnace_opening.png, glass_clean.png")


if __name__ == "__main__":
    main()

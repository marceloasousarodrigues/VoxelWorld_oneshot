"""Vendor the block textures used by the M17 Godot game into the Godot project.

The M17 Godot project must be self-contained inside ``prototypes/m17/godot``.
This script copies the already-present repository textures (the M9/M11/M12/M14
production texture sources recorded in ``config/texture_manifest.json``) into
``prototypes/m17/godot/assets/textures`` and writes a machine readable manifest
that the Godot runtime uses to build its texture array.

It performs no downloads, requires only the standard library, is idempotent and
never deletes anything.

Usage:
    python prototypes/m17/godot/tools/import_textures.py
"""

from __future__ import annotations

import json
import shutil
import struct
from pathlib import Path

SCRIPT = Path(__file__).resolve()
GODOT_DIR = SCRIPT.parents[1]
REPO_ROOT = SCRIPT.parents[4]
SOURCE_ROOT = REPO_ROOT / "voxel_textures"
DEST_ROOT = GODOT_DIR / "assets" / "textures"
MANIFEST_PATH = GODOT_DIR / "assets" / "texture_sources.json"

MINETEST = "MINETEST_TEXTURES"
MINETEST_LICENSE = (
    "Minetest default game texture pack; refer to that pack's bundled license "
    "(CC BY-SA 3.0 for the default game). Already used by the M12/M14 production "
    "milestones via config/texture_manifest.json."
)
LOCAL_HD_LICENSE = "CC0 (ambientCG, https://ambientcg.com), recorded in config/texture_manifest.json for M11."

# key -> (repo-relative source path, license note, human description)
TEXTURES: dict[str, tuple[str, str, str]] = {
    # --- core terrain -------------------------------------------------------
    "grass_top": (f"{MINETEST}/default_grass.png", MINETEST_LICENSE, "GRASS top face"),
    "grass_side": ("blocks/grass_side_composite.png", "Derived composite already used by M12 (Minetest default pack derivative).", "GRASS side face"),
    "dirt": (f"{MINETEST}/default_dirt.png", MINETEST_LICENSE, "DIRT"),
    "stone": (f"{MINETEST}/default_stone.png", MINETEST_LICENSE, "STONE"),
    "cobble": (f"{MINETEST}/default_cobble.png", MINETEST_LICENSE, "COBBLESTONE / STONE drop"),
    "sand": (f"{MINETEST}/default_sand.png", MINETEST_LICENSE, "SAND"),
    "sandstone": (f"{MINETEST}/default_sandstone.png", MINETEST_LICENSE, "SANDSTONE"),
    "gravel": (f"{MINETEST}/default_gravel.png", MINETEST_LICENSE, "GRAVEL"),
    "snow": (f"{MINETEST}/default_snow.png", MINETEST_LICENSE, "SNOW"),
    "dry_grass_top": (f"{MINETEST}/default_dry_grass.png", MINETEST_LICENSE, "DRY_GRASS top (savanna)"),
    "dry_grass_side": (f"{MINETEST}/default_dry_grass_side.png", MINETEST_LICENSE, "DRY_GRASS side (savanna)"),
    "clay": (f"{MINETEST}/default_clay.png", MINETEST_LICENSE, "CLAY"),
    "bedrock": (f"{MINETEST}/default_obsidian_block.png", MINETEST_LICENSE, "BEDROCK (dark unbreakable rock)"),
    "obsidian": (f"{MINETEST}/default_obsidian_block.png", MINETEST_LICENSE, "OBSIDIAN (dark volcanic rock)"),
    "brick": (f"{MINETEST}/default_brick.png", MINETEST_LICENSE, "BRICK"),
    "stone_brick": (f"{MINETEST}/default_stone_brick.png", MINETEST_LICENSE, "STONE_BRICK"),
    "mossy_cobble": (f"{MINETEST}/default_mossycobble.png", MINETEST_LICENSE, "MOSSY_COBBLESTONE"),
    # --- ores --------------------------------------------------------------
    "coal_ore": (f"{MINETEST}/default_mineral_coal.png", MINETEST_LICENSE, "COAL_ORE"),
    "iron_ore": (f"{MINETEST}/default_mineral_iron.png", MINETEST_LICENSE, "IRON_ORE"),
    "gold_ore": (f"{MINETEST}/default_mineral_gold.png", MINETEST_LICENSE, "GOLD_ORE"),
    "diamond_ore": (f"{MINETEST}/default_mineral_diamond.png", MINETEST_LICENSE, "DIAMOND_ORE"),
    # --- wood --------------------------------------------------------------
    "oak_log_side": (f"{MINETEST}/default_tree.png", MINETEST_LICENSE, "OAK_LOG side"),
    "oak_log_top": (f"{MINETEST}/default_tree_top.png", MINETEST_LICENSE, "OAK_LOG top/bottom"),
    "oak_leaves": (f"{MINETEST}/default_leaves.png", MINETEST_LICENSE, "OAK_LEAVES (alpha cutout)"),
    "planks": (f"{MINETEST}/default_wood.png", MINETEST_LICENSE, "PLANKS"),
    "pine_log_side": (f"{MINETEST}/default_pine_tree.png", MINETEST_LICENSE, "PINE_LOG side"),
    "pine_log_top": (f"{MINETEST}/default_pine_tree_top.png", MINETEST_LICENSE, "PINE_LOG top/bottom"),
    "pine_leaves": (f"{MINETEST}/default_pine_needles.png", MINETEST_LICENSE, "PINE_LEAVES (alpha cutout)"),
    # --- misc / plants -----------------------------------------------------
    "cactus_side": (f"{MINETEST}/default_cactus_side.png", MINETEST_LICENSE, "CACTUS side"),
    "cactus_top": (f"{MINETEST}/default_cactus_top.png", MINETEST_LICENSE, "CACTUS top"),
    "glass": (f"{MINETEST}/default_glass.png", MINETEST_LICENSE, "GLASS"),
    "water": ("blocks/water.png", "Present in the repository since M9; small placeholder water tile.", "WATER tile (static fallback)"),
    "water_anim": (f"{MINETEST}/default_water_source_animated.png", MINETEST_LICENSE, "WATER surface, 8-frame animated strip"),
    "deco_grass_1": (f"{MINETEST}/default_grass_1.png", MINETEST_LICENSE, "grass tuft decoration"),
    "deco_grass_2": (f"{MINETEST}/default_grass_2.png", MINETEST_LICENSE, "grass tuft decoration"),
    "deco_grass_3": (f"{MINETEST}/default_grass_3.png", MINETEST_LICENSE, "grass tuft decoration"),
    "deco_grass_4": (f"{MINETEST}/default_grass_4.png", MINETEST_LICENSE, "grass tuft decoration"),
    "deco_grass_5": (f"{MINETEST}/default_grass_5.png", MINETEST_LICENSE, "grass tuft decoration"),
    "deco_dry_grass": (f"{MINETEST}/default_dry_grass_1.png", MINETEST_LICENSE, "dry grass tuft decoration"),
    "deco_jungle_grass": (f"{MINETEST}/default_junglegrass.png", MINETEST_LICENSE, "tall grass tuft decoration"),
}

# Animated strips are excluded from the texture array (uniform size requirement)
# and loaded as their own texture.  key -> source key of the strip above.
ANIMATED = {
    "water_anim": {"frames": 8},
}


def png_size(path: Path) -> tuple[int, int]:
    header = path.read_bytes()[:26]
    width, height = struct.unpack(">II", header[16:24])
    return width, height


def main() -> int:
    if not SOURCE_ROOT.is_dir():
        raise SystemExit(f"Missing texture source root: {SOURCE_ROOT}")
    DEST_ROOT.mkdir(parents=True, exist_ok=True)
    entries: dict[str, dict[str, object]] = {}
    copied = 0
    for key, (relative, license_note, description) in sorted(TEXTURES.items()):
        source = SOURCE_ROOT / relative
        if not source.is_file():
            raise SystemExit(f"Missing texture source for {key}: {source}")
        destination = DEST_ROOT / source.name
        if not destination.exists() or destination.read_bytes() != source.read_bytes():
            shutil.copyfile(source, destination)
            copied += 1
        width, height = png_size(source)
        entry: dict[str, object] = {
            "key": key,
            "file": destination.name,
            "source": f"voxel_textures/{relative}",
            "license": license_note,
            "description": description,
            "width": width,
            "height": height,
        }
        if key in ANIMATED:
            frames = ANIMATED[key]["frames"]
            if height != width * frames:
                raise SystemExit(f"{key}: expected {frames} stacked frames, source is {width}x{height}")
            entry["frames"] = frames
        entries[key] = entry

    MANIFEST_PATH.write_text(
        json.dumps(
            {
                "version": 1,
                "generated_by": "prototypes/m17/godot/tools/import_textures.py",
                "note": (
                    "Vendored copies of repository textures for the M17 Godot project. "
                    "No file was downloaded; each entry records the in-repo source path."
                ),
                "textures": entries,
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"Vendored {len(entries)} textures into {DEST_ROOT.relative_to(REPO_ROOT)} ({copied} copied, {len(entries) - copied} unchanged)")
    print(f"Wrote {MANIFEST_PATH.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

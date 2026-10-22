import json
import sys
from pathlib import Path

import numpy as np

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))
sys.path.insert(0, str(REPO_ROOT / "scripts"))

import pack_textures as pt  # noqa: E402

from block_data import BlockType, get_block_face_textures  # noqa: E402


MANIFEST_PATH = REPO_ROOT / "config" / "texture_manifest.json"


def test_manifest_still_maps_water_to_blocks_water():
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    water = manifest["blocks"]["WATER"]
    for face in ("top", "side", "bottom"):
        assert water[face].endswith("blocks/water.png")


def test_water_asset_is_16x16_rgba_with_expected_alpha():
    from PIL import Image

    im = Image.open(REPO_ROOT / "voxel_textures" / "blocks" / "water.png")
    assert im.size == (16, 16)
    assert im.mode == "RGBA"

    rgba = np.asarray(im.convert("RGBA"))
    alpha = rgba[:, :, 3]
    assert int(alpha.min()) == 130
    assert int(alpha.max()) == 215
    assert int((alpha == 0).sum()) == 0


def test_atlas_includes_water_tile(tmp_path):
    out_image = tmp_path / "gen_atlas.png"
    out_map = tmp_path / "atlas_map.json"

    pt.build_atlas(
        manifest_path=MANIFEST_PATH,
        out_image=out_image,
        out_map=out_map,
        base_dir=REPO_ROOT,
        max_size=2048,
    )

    data = json.loads(out_map.read_text(encoding="utf-8"))
    faces = get_block_face_textures(BlockType.WATER)
    for key in ("top", "side", "bottom"):
        assert faces[key] in data["tiles"]


def test_minetest_water_textures_are_incompatible_with_static_atlas():
    """Documents the D7 decision: Minetest stills are opaque 128x128 and the
    animated variants are 128x1024 eight-frame strips, so they cannot be
    consumed by the current static single-frame atlas path."""
    from PIL import Image

    still = Image.open(REPO_ROOT / "voxel_textures" / "minetest_textures" / "default_water.png")
    animated = Image.open(
        REPO_ROOT / "voxel_textures" / "minetest_textures" / "default_water_source_animated.png"
    )

    assert still.size == (128, 128)
    assert animated.size == (128, 1024)
    assert animated.size[1] == still.size[1] * 8

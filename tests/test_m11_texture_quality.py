import sys
from pathlib import Path

from PIL import Image

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

import texture_config as tc

HD_ASSETS = (
    "grass_top_hd.png",
    "grass_side_hd.png",
    "dirt_hd.png",
    "stone_hd.png",
    "sand_hd.png",
)


def test_all_manifest_references_resolve():
    manifest = tc.load_manifest()
    refs = [
        faces[face]
        for faces in manifest["blocks"].values()
        for face in ("top", "side", "bottom")
        if faces.get(face)
    ]
    assert refs
    missing = [r for r in refs if not (tc.REPO_ROOT / r).is_file()]
    assert missing == []


def test_hd_assets_are_png_256():
    for name in HD_ASSETS:
        path = REPO_ROOT / "voxel_textures" / "blocks" / name
        assert path.is_file(), name
        with Image.open(path) as image:
            assert image.format == "PNG", name
            assert image.size == (256, 256), (name, image.size)


def test_grass_faces_are_distinct_hd_assets():
    faces = tc.block_face_textures("GRASS")
    assert faces["top"] != faces["side"]
    assert faces["side"] != faces["bottom"]
    assert faces["top"] != faces["bottom"]
    for face in ("top", "side", "bottom"):
        assert (tc.REPO_ROOT / faces[face]).is_file()


def test_water_texture_preserved():
    faces = tc.block_face_textures("WATER")
    assert faces["top"] == "voxel_textures/blocks/water.png"
    assert (tc.REPO_ROOT / faces["top"]).is_file()


def test_atlas_entries_and_uvs_valid():
    atlas_map = tc.load_atlas_map()
    assert atlas_map is not None
    width = atlas_map["atlas"]["width"]
    height = atlas_map["atlas"]["height"]
    assert width <= 2048 and height <= 2048
    assert atlas_map["atlas"]["filter"] == "nearest"
    for path, tile in atlas_map["tiles"].items():
        assert tile["u0"] == tile["x"] / width, path
        assert tile["v0"] == tile["y"] / height, path
        assert tile["u1"] == (tile["x"] + tile["w"]) / width, path
        assert tile["v1"] == (tile["y"] + tile["h"]) / height, path
        assert 0.0 < tile["u0"] < tile["u1"] < 1.0, path
        assert 0.0 < tile["v0"] < tile["v1"] < 1.0, path

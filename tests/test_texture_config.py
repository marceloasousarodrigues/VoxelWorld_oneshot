import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

import texture_config as tc


def test_manifest_loads_and_exposes_faces():
    assert tc.block_face_textures("GRASS") == {
        "top": "voxel_textures/MINETEST_TEXTURES/default_grass.png",
        "side": "voxel_textures/blocks/grass_side_composite.png",
        "bottom": "voxel_textures/MINETEST_TEXTURES/default_dirt.png",
    }


def test_unknown_block_is_all_none():
    assert tc.block_face_textures("NOT_A_BLOCK") == {
        "top": None,
        "side": None,
        "bottom": None,
    }


def test_air_faces_are_none():
    assert tc.block_face_textures("AIR") == {"top": None, "side": None, "bottom": None}


def test_atlas_and_legacy_paths_are_centralized():
    assert tc.ATLAS_IMAGE_PATH.name == "gen_atlas.png"
    assert tc.ATLAS_MAP_PATH.name == "atlas_map.json"
    assert tc.LEGACY_ATLAS_PATH.name == "blocks.png"
    assert tc.TEXTURE_M9 == "voxel_textures/gen_atlas.png"
    assert tc.TEXTURE_LEGACY == "voxel_textures/blocks.png"


def test_atlas_assets_available_matches_files():
    expected = tc.ATLAS_IMAGE_PATH.is_file() and tc.ATLAS_MAP_PATH.is_file()
    assert tc.atlas_assets_available() is expected


def test_load_atlas_map_returns_tiles_when_available():
    atlas_map = tc.load_atlas_map()
    if tc.atlas_assets_available():
        assert atlas_map is not None
        assert "tiles" in atlas_map
    else:
        assert atlas_map is None


def test_missing_manifest_degrades_gracefully(tmp_path, monkeypatch):
    monkeypatch.setattr(tc, "MANIFEST_PATH", tmp_path / "does_not_exist.json")
    tc.reset_cache()
    try:
        assert tc.load_manifest() == {}
        assert tc.block_face_textures("GRASS") == {
            "top": None,
            "side": None,
            "bottom": None,
        }
    finally:
        tc.reset_cache()

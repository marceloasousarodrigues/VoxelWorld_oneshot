import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

sys.path.insert(0, str(REPO_ROOT / "scripts"))

from block_data import BlockType, get_block_face_textures, is_block_solid, is_block_transparent
import texture_config as tc
import pack_textures as pt


def test_new_block_types_exist():
    assert int(BlockType.OAK_LOG) == 6
    assert int(BlockType.OAK_LEAVES) == 7


def test_tree_blocks_are_solid_and_opaque():
    assert is_block_solid(BlockType.OAK_LOG) is True
    assert is_block_solid(BlockType.OAK_LEAVES) is True
    assert is_block_transparent(BlockType.OAK_LOG) is False
    assert is_block_transparent(BlockType.OAK_LEAVES) is False


def test_tree_face_textures_resolve():
    log = get_block_face_textures(BlockType.OAK_LOG)
    leaves = get_block_face_textures(BlockType.OAK_LEAVES)
    assert log["top"] == "voxel_textures/MINETEST_TEXTURES/default_tree_top.png"
    assert log["side"] == "voxel_textures/MINETEST_TEXTURES/default_tree.png"
    assert leaves["top"] == leaves["side"] == leaves["bottom"] == "voxel_textures/MINETEST_TEXTURES/default_leaves.png"


def test_decoration_textures_exposed():
    deco = tc.decoration_textures()
    assert deco["grass_tuft_1"] == "voxel_textures/MINETEST_TEXTURES/default_grass_1.png"
    assert len(deco) == 5


def test_packer_collects_decorations():
    sources = pt.collect_sources(pt.load_manifest(pt.DEFAULT_MANIFEST))
    assert "voxel_textures/MINETEST_TEXTURES/default_grass_1.png" in sources
    assert "voxel_textures/MINETEST_TEXTURES/default_leaves.png" in sources


def test_atlas_contains_new_tiles():
    atlas_map = tc.load_atlas_map()
    assert atlas_map is not None
    for key in ("default_tree.png", "default_tree_top.png", "default_leaves.png",
                "default_grass_1.png"):
        assert any(t.endswith(key) for t in atlas_map["tiles"])

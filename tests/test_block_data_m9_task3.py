from block_data import (
    BlockType,
    get_block_face_textures,
    get_block_texture,
    is_block_transparent,
)
from texture_config import block_face_textures


def test_face_textures_are_sourced_from_manifest():
    for block_type in BlockType:
        assert get_block_face_textures(block_type) == block_face_textures(block_type.name)


def test_grass_face_textures_match_manifest_convention():
    faces = get_block_face_textures(BlockType.GRASS)
    assert set(faces.keys()) == {"top", "side", "bottom"}
    assert faces == block_face_textures("GRASS")
    assert faces["top"] == "voxel_textures/MINETEST_TEXTURES/default_grass.png"
    assert faces["side"] == "voxel_textures/blocks/grass_side_composite.png"
    assert faces["bottom"] == "voxel_textures/MINETEST_TEXTURES/default_dirt.png"
    assert len({faces["top"], faces["side"], faces["bottom"]}) == 3


def test_get_block_face_textures_air_is_all_none():
    faces = get_block_face_textures(BlockType.AIR)
    assert faces == {"top": None, "side": None, "bottom": None}


def test_is_block_transparent_water():
    assert is_block_transparent(BlockType.WATER) is True
    assert is_block_transparent(BlockType.GRASS) is False
    assert is_block_transparent(BlockType.AIR) is False


def test_get_block_texture_backward_compat():
    assert get_block_texture(BlockType.GRASS) == "grass.png"

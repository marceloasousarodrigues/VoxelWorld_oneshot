import pytest

from block_data import (
    BlockType,
    get_block_face_textures,
    get_block_texture,
    is_block_transparent,
)


def test_get_block_face_textures_grass_matches_manifest_convention():
    faces = get_block_face_textures(BlockType.GRASS)
    assert set(faces.keys()) == {"top", "side", "bottom"}
    assert faces["top"] == "voxel_textures/blocks/grass_top.png"
    assert faces["side"] == "voxel_textures/blocks/grass_side.png"
    assert faces["bottom"] == "voxel_textures/blocks/dirt.png"


def test_get_block_face_textures_air_is_all_none():
    faces = get_block_face_textures(BlockType.AIR)
    assert faces == {"top": None, "side": None, "bottom": None}


def test_is_block_transparent_water():
    assert is_block_transparent(BlockType.WATER) is True
    assert is_block_transparent(BlockType.GRASS) is False
    assert is_block_transparent(BlockType.AIR) is False


def test_get_block_texture_backward_compat():
    assert get_block_texture(BlockType.GRASS) == "grass.png"

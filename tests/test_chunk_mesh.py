import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from block_data import BlockType
from chunk import Chunk
from chunk_mesh import generate_chunk_mesh
from world import World


GRASS_TOP_PATH = "voxel_textures/blocks/grass_top.png"
GRASS_SIDE_PATH = "voxel_textures/blocks/grass_side.png"
DIRT_PATH = "voxel_textures/blocks/dirt.png"


def _make_atlas_map():
    return {
        "version": 1,
        "atlas": {"width": 1, "height": 1, "padding": 2, "filter": "nearest"},
        "tiles": {
            GRASS_TOP_PATH: {"u0": 0.1, "v0": 0.25, "u1": 0.2, "v1": 0.5},
            GRASS_SIDE_PATH: {"u0": 0.2, "v0": 0.1, "u1": 0.3, "v1": 0.6},
            DIRT_PATH: {"u0": 0.3, "v0": 0.2, "u1": 0.4, "v1": 0.4},
        },
    }


def _tile_to_face_uvs(tile):
    u0 = tile["u0"]
    u1 = tile["u1"]
    v_top = 1.0 - tile["v0"]
    v_bottom = 1.0 - tile["v1"]
    return [(u0, v_top), (u1, v_top), (u1, v_bottom), (u0, v_bottom)]


def test_face_aware_uv_mapping_top_side_bottom():
    chunk = Chunk(0, 0, 0)
    chunk.set_block(0, 0, 0, BlockType.GRASS)

    atlas_map = _make_atlas_map()

    _, _, uvs = generate_chunk_mesh(chunk, atlas_map=atlas_map)

    assert len(uvs) == 6 * 4

    top_expected = _tile_to_face_uvs(atlas_map["tiles"][GRASS_TOP_PATH])
    side_expected = _tile_to_face_uvs(atlas_map["tiles"][GRASS_SIDE_PATH])
    bottom_expected = _tile_to_face_uvs(atlas_map["tiles"][DIRT_PATH])

    assert uvs[12:16] == pytest.approx(top_expected)
    assert uvs[8:12] == pytest.approx(bottom_expected)

    assert uvs[0:4] == pytest.approx(side_expected)
    assert uvs[4:8] == pytest.approx(side_expected)
    assert uvs[16:20] == pytest.approx(side_expected)
    assert uvs[20:24] == pytest.approx(side_expected)


def test_face_culling_neighbor_solid_reduces_uv_count():
    chunk = Chunk(0, 0, 0)
    chunk.set_block(0, 0, 0, BlockType.GRASS)
    chunk.set_block(1, 0, 0, BlockType.GRASS)

    atlas_map = _make_atlas_map()

    _, _, uvs = generate_chunk_mesh(chunk, atlas_map=atlas_map)

    assert len(uvs) == 10 * 4


def test_chunk_boundary_uses_world_neighbor():
    world = World()
    world.set_block(15, 0, 0, BlockType.DIRT)
    world.set_block(16, 0, 0, BlockType.DIRT)

    atlas_map = {
        "version": 1,
        "atlas": {"width": 1, "height": 1, "padding": 2, "filter": "nearest"},
        "tiles": {DIRT_PATH: {"u0": 0.3, "v0": 0.2, "u1": 0.4, "v1": 0.8}},
    }

    chunk = world.get_chunk(0, 0, 0)
    _, _, uvs = generate_chunk_mesh(chunk, world=world, atlas_map=atlas_map)

    assert len(uvs) == 5 * 4

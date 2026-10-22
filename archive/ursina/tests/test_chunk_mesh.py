import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from block_data import BlockType
from chunk import Chunk
from chunk_mesh import generate_chunk_mesh
from world import World


GRASS_TOP_PATH = "voxel_textures/MINETEST_TEXTURES/default_grass.png"
GRASS_SIDE_PATH = "voxel_textures/blocks/grass_side_composite.png"
DIRT_PATH = "voxel_textures/MINETEST_TEXTURES/default_dirt.png"


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


# Per-face UV corner order contract (mirrors chunk_mesh._FACE_UV_ORDER).
# Corners are [top-left, top-right, bottom-right, bottom-left].
_FACE_ORDER = {
    0: (1, 0, 3, 2),  # Back
    1: (3, 2, 1, 0),  # Front
    2: (3, 2, 1, 0),  # Bottom
    3: (3, 2, 1, 0),  # Top
    4: (3, 0, 1, 2),  # Left
    5: (3, 0, 1, 2),  # Right
}


def _oriented(tile, face_index):
    corners = _tile_to_face_uvs(tile)
    return [corners[i] for i in _FACE_ORDER[face_index]]


def test_face_aware_uv_mapping_top_side_bottom():
    chunk = Chunk(0, 0, 0)
    chunk.set_block(0, 0, 0, BlockType.GRASS)

    atlas_map = _make_atlas_map()

    _, _, uvs = generate_chunk_mesh(chunk, atlas_map=atlas_map)

    assert len(uvs) == 6 * 4

    side = atlas_map["tiles"][GRASS_SIDE_PATH]
    top = atlas_map["tiles"][GRASS_TOP_PATH]
    bottom = atlas_map["tiles"][DIRT_PATH]

    # Face order: 0 Back, 1 Front, 2 Bottom, 3 Top, 4 Left, 5 Right.
    assert uvs[0:4] == pytest.approx(_oriented(side, 0))
    assert uvs[4:8] == pytest.approx(_oriented(side, 1))
    assert uvs[8:12] == pytest.approx(_oriented(bottom, 2))
    assert uvs[12:16] == pytest.approx(_oriented(top, 3))
    assert uvs[16:20] == pytest.approx(_oriented(side, 4))
    assert uvs[20:24] == pytest.approx(_oriented(side, 5))


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

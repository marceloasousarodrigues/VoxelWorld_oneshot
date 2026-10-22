import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from block_data import BlockType
from chunk import Chunk
from chunk_mesh import generate_chunk_mesh_split


def _split(chunk, world=None):
    return generate_chunk_mesh_split(chunk, world=world)


def test_single_water_block_exposes_six_faces():
    chunk = Chunk(0, 0, 0)
    chunk.set_block(0, 0, 0, BlockType.WATER)

    _vo, _to, _uo, _vt, _tt, uvs_t = _split(chunk)

    assert len(uvs_t) // 4 == 6


def test_adjacent_water_internal_faces_are_culled():
    chunk = Chunk(0, 0, 0)
    chunk.set_block(0, 0, 0, BlockType.WATER)
    chunk.set_block(1, 0, 0, BlockType.WATER)

    _vo, _to, _uo, _vt, _tt, uvs_t = _split(chunk)

    # 5 exposed faces each; the shared internal pair is culled.
    assert len(uvs_t) // 4 == 10


def test_water_face_against_solid_is_culled():
    chunk = Chunk(0, 0, 0)
    chunk.set_block(0, 0, 0, BlockType.WATER)
    chunk.set_block(1, 0, 0, BlockType.STONE)

    _vo, _to, _uo, _vt, _tt, uvs_t = _split(chunk)

    # Water's face toward the solid is hidden; the other five remain.
    assert len(uvs_t) // 4 == 5


def test_solid_face_against_water_is_rendered():
    chunk = Chunk(0, 0, 0)
    chunk.set_block(0, 0, 0, BlockType.WATER)
    chunk.set_block(1, 0, 0, BlockType.STONE)

    _vo, _to, uvs_o, _vt, _tt, _ut = _split(chunk)

    # The opaque pass keeps the stone face toward water visible.
    assert len(uvs_o) // 4 == 6


def test_water_geometry_is_full_cube_height():
    # M13 non-goal: partial-height water. Water stays a full-height cube.
    chunk = Chunk(0, 0, 0)
    chunk.set_block(0, 0, 0, BlockType.WATER)

    _vo, _to, _uo, vt, _tt, _ut = _split(chunk)

    ys = sorted({vt[i] for i in range(1, len(vt), 3)})
    assert ys == [0, 1]


def test_cross_chunk_water_water_faces_are_culled():
    from world import World

    world = World()
    world.get_chunk(0, 0, 0)
    world.get_chunk(1, 0, 0)
    world.set_block(15, 0, 0, BlockType.WATER)
    world.set_block(16, 0, 0, BlockType.WATER)

    chunk = world.chunks[(0, 0, 0)]
    _vo, _to, _uo, _vt, _tt, uvs_t = _split(chunk, world=world)

    # Water on the +X boundary sees water in the neighbour chunk: 5 faces.
    assert len(uvs_t) // 4 == 5

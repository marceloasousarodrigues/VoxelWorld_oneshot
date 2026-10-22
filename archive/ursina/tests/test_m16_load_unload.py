"""M16 Task 3 — World chunk lifecycle.

Loading must register a chunk exactly once and give it exactly one rendered
entity. Unloading must release the registry entry and the rendered resources,
and must be idempotent. Repeated transitions must never leave duplicates.
"""

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from terrain_generation import TerrainGenerator  # noqa: E402
from world import World  # noqa: E402


def test_load_chunk_registers_once_and_creates_one_entity():
    world = World()
    generator = TerrainGenerator()

    chunk = world.load_chunk(4, 0, 4, terrain_generator=generator)

    assert world.chunks[(4, 0, 4)] is chunk
    assert chunk.entity is not None

    # Loading again must not duplicate the chunk or its entity.
    again = world.load_chunk(4, 0, 4, terrain_generator=generator)
    assert again is chunk
    assert len(world.chunks) == 1


def test_load_chunk_returns_existing_chunk_without_regenerating():
    world = World()
    generator = TerrainGenerator()
    chunk = world.load_chunk(0, 0, 0, terrain_generator=generator)

    from block_data import BlockType

    chunk.set_block(0, 0, 0, BlockType.STONE)
    # An already-registered chunk is returned untouched, not regenerated.
    same = world.load_chunk(0, 0, 0, terrain_generator=generator)
    assert same is chunk
    assert chunk.get_block(0, 0, 0) == BlockType.STONE


def test_load_chunk_generates_a_previously_created_empty_chunk():
    world = World()
    generator = TerrainGenerator()

    # A chunk created on demand (e.g. by an edit) before streaming reaches it is
    # registered but has no terrain. Loading it must populate it, not treat the
    # empty placeholder as a finished chunk.
    empty = world.get_chunk(3, 0, 3)
    assert int(empty.blocks.max()) == 0

    chunk = world.load_chunk(3, 0, 3, terrain_generator=generator)

    assert chunk is empty
    assert int(chunk.blocks.max()) != 0
    assert chunk.entity is not None


def test_unload_chunk_releases_entity_and_registry_entry():
    world = World()
    generator = TerrainGenerator()
    chunk = world.load_chunk(0, 0, 0, terrain_generator=generator)
    world.dirty((0, 0, 0))

    assert world.unload_chunk(0, 0, 0) is True

    assert (0, 0, 0) not in world.chunks
    assert (0, 0, 0) not in world.dirty_chunks
    assert chunk.entity is None
    assert chunk.entity_transparent is None

    # Unloading something that is not loaded is a no-op, not an error.
    assert world.unload_chunk(0, 0, 0) is False


def test_repeated_load_unload_leaves_no_duplicates():
    world = World()
    generator = TerrainGenerator()

    for _ in range(5):
        world.load_chunk(2, 0, -3, terrain_generator=generator)
        assert len(world.chunks) == 1
        assert world.unload_chunk(2, 0, -3) is True
        assert world.chunks == {}

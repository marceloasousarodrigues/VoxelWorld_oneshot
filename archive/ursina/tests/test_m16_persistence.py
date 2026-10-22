"""M16 Task 3 — the documented persistence policy.

Regenerable state (base terrain, vegetation, lake water) is reproduced
deterministically. Authoritative state (player block edits and cleared
decorations) survives an unload/re-entry through the in-memory edit overlay.
"""

import hashlib
import sys
from pathlib import Path

import numpy as np

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from block_data import BlockType  # noqa: E402
from terrain_generation import TerrainGenerator  # noqa: E402
from world import World  # noqa: E402


def _fingerprint(chunk):
    return (
        hashlib.sha256(chunk.blocks.tobytes()).hexdigest(),
        hashlib.sha256(chunk.decorations.tobytes()).hexdigest(),
        hashlib.sha256(chunk.water_levels.tobytes()).hexdigest(),
        hashlib.sha256(chunk.water_sources.tobytes()).hexdigest(),
    )


def test_overrides_only_record_external_edits():
    world = World()
    generator = TerrainGenerator()
    world.load_chunk(0, 0, 0, terrain_generator=generator)

    # Generation writes through the Chunk, so it must not populate the overlay.
    assert world.block_overrides == {}
    assert world.decoration_overrides == {}

    world.set_block(1, 1, 1, BlockType.STONE)
    assert world.block_overrides[(1, 1, 1)] == BlockType.STONE


def test_block_edit_survives_unload_and_reentry():
    world = World()
    generator = TerrainGenerator()
    world.load_chunk(0, 0, 0, terrain_generator=generator)

    from terrain_generation import in_lake, surface_height

    # Pick a dry grass surface column inside the chunk.
    column = None
    for local_x in range(16):
        for local_z in range(16):
            if in_lake(local_x, local_z):
                continue
            surface = surface_height(generator.seed, local_x, local_z)
            if world.get_block(local_x, surface, local_z) == BlockType.GRASS:
                column = (local_x, surface, local_z)
                break
        if column is not None:
            break
    assert column is not None, "origin chunk should contain dry grass"
    local_x, surface, local_z = column

    world.set_block(local_x, surface, local_z, BlockType.AIR)

    world.unload_chunk(0, 0, 0)
    chunk = world.load_chunk(0, 0, 0, terrain_generator=generator)

    assert chunk.get_block(local_x, surface, local_z) == BlockType.AIR


def test_cleared_decoration_survives_reentry():
    world = World()
    generator = TerrainGenerator()
    chunk = world.load_chunk(0, 0, 0, terrain_generator=generator)

    decorated = np.argwhere(chunk.decorations > 0)
    assert decorated.size > 0, "expected a grass tuft in the origin chunk"
    local_x, local_y, local_z = (int(value) for value in decorated[0])
    assert local_y >= 1

    # Breaking the supporting block clears the tuft above it.
    world.set_block(local_x, local_y - 1, local_z, BlockType.AIR)
    assert chunk.get_decoration(local_x, local_y, local_z) == 0

    world.unload_chunk(0, 0, 0)
    reloaded = world.load_chunk(0, 0, 0, terrain_generator=generator)

    assert reloaded.get_decoration(local_x, local_y, local_z) == 0


def test_placed_block_over_regenerated_lake_water_is_not_water():
    world = World()
    generator = TerrainGenerator()
    chunk = world.load_chunk(0, 0, 0, terrain_generator=generator)

    # The deterministic lake fills y = 2..4 at the origin column.
    assert world.get_block(0, 2, 0) == BlockType.WATER

    world.set_block(0, 2, 0, BlockType.STONE)
    assert chunk.get_water_level(0, 2, 0) == 0

    world.unload_chunk(0, 0, 0)
    reloaded = world.load_chunk(0, 0, 0, terrain_generator=generator)

    assert reloaded.get_block(0, 2, 0) == BlockType.STONE
    assert reloaded.get_water_level(0, 2, 0) == 0
    assert reloaded.get_water_source(0, 2, 0) is False


def test_regenerated_terrain_is_identical_without_edits():
    world = World()
    generator = TerrainGenerator()
    chunk = world.load_chunk(0, 0, 0, terrain_generator=generator)
    before = _fingerprint(chunk)

    world.unload_chunk(0, 0, 0)
    reloaded = world.load_chunk(0, 0, 0, terrain_generator=generator)

    assert _fingerprint(reloaded) == before


def test_reads_never_create_chunks():
    world = World()
    for x in range(-40, 40, 7):
        for z in range(-40, 40, 7):
            world.get_block(x, 8, z)
            world.get_water(x, 8, z)
            world.is_source(x, 8, z)
    assert world.chunks == {}

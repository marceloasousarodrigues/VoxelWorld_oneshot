"""M15 Task 9 - bounded chunk storage and the active-region contract.

These tests document what is true today rather than asserting a feature that
does not exist: there is no chunk unload path, so the loaded set *is* the active
set, and the unloaded count must be reported as unknown, never fabricated.
"""

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from block_data import BlockType  # noqa: E402
from terrain_generation import TerrainGenerator  # noqa: E402
from water import WaterSimulation  # noqa: E402
from world import World  # noqa: E402

sys.path.insert(0, str(REPO_ROOT / "scripts"))
from profile_m15 import chunk_counts, numpy_bytes, pending_work  # noqa: E402

PER_CHUNK_BYTES = 28_672  # 16,384 blocks + 4,096 levels + 4,096 sources + 4,096 decorations


def _per_chunk_bytes(world):
    return sum(
        int(array.nbytes)
        for chunk in world.chunks.values()
        for array in (
            chunk.blocks,
            chunk.water_levels,
            chunk.water_sources,
            chunk.decorations,
        )
    )


def test_per_chunk_numpy_storage_is_28k():
    world = World()
    chunk = world.get_chunk(0, 0, 0)
    total = (
        int(chunk.blocks.nbytes)
        + int(chunk.water_levels.nbytes)
        + int(chunk.water_sources.nbytes)
        + int(chunk.decorations.nbytes)
    )
    assert total == PER_CHUNK_BYTES


def test_storage_scales_linearly_with_loaded_chunks():
    world = World()
    for chunk_x in range(4):
        for chunk_z in range(4):
            world.get_chunk(chunk_x, 0, chunk_z)

    assert len(world.chunks) == 16
    assert _per_chunk_bytes(world) == 16 * PER_CHUNK_BYTES
    assert numpy_bytes(world) == 16 * PER_CHUNK_BYTES


def test_read_only_traversal_does_not_create_chunks():
    world = World()
    TerrainGenerator().generate_world(world)
    loaded = set(world.chunks)

    # Reads over generated and ungenerated coordinates must never create.
    for x in range(-40, 40, 7):
        for z in range(-40, 40, 7):
            world.get_block(x, 8, z)
            world.get_water(x, 8, z)
            world.is_source(x, 8, z)

    assert set(world.chunks) == loaded
    assert loaded  # sanity: the generated world has chunks


def test_chunk_counts_report_visible_active_and_null_unloaded():
    world = World()
    world.get_chunk(0, 0, 0)
    world.get_chunk(1, 0, 0)
    world.dirty_chunks.clear()
    world.set_block(1, 1, 1, BlockType.STONE)

    counts = chunk_counts(world)
    assert counts["loaded"] == 2
    # No renderer in this test: no entity was created for either chunk.
    assert counts["visible"] == 0
    assert counts["active"] == 1
    # No unload path exists, so this is honestly unknown, not zero.
    assert counts["unloaded"] is None


def test_pending_work_returns_to_zero_after_a_session():
    world = World()
    TerrainGenerator().generate_world(world)
    water = WaterSimulation(world)
    water.seed_all_sources()

    # Simulate a session: edit some blocks, run water to quiescence, reconcile.
    for index in range(20):
        world.set_block(index % 16, 8, index % 16, BlockType.STONE)
    while water.has_pending_work():
        water.tick()
    while world.dirty_chunks:
        world.reconcile()

    pending = pending_work(world, water)
    assert pending["dirty_chunks"] == 0
    assert pending["pending_seeds"] == 0
    assert pending["active_job"] is False


if __name__ == "__main__":
    test_per_chunk_numpy_storage_is_28k()
    test_storage_scales_linearly_with_loaded_chunks()
    test_read_only_traversal_does_not_create_chunks()
    test_chunk_counts_report_visible_active_and_null_unloaded()
    test_pending_work_returns_to_zero_after_a_session()
    print("M15 memory growth tests passed!")

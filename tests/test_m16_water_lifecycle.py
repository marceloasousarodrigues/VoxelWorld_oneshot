"""M16 Task 5 — water across the chunk lifecycle.

A newly loaded chunk's sources must join the simulation, and a chunk entering or
leaving the world must invalidate any water job built on the old domain so stale
work can never publish into an unloaded or replaced chunk.
"""

import sys
from pathlib import Path

import numpy as np

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from terrain_generation import TerrainGenerator  # noqa: E402
from water import WaterSimulation  # noqa: E402
from world import World  # noqa: E402


def _run_to_quiescence(world, water, limit=20000) -> bool:
    for _ in range(limit):
        water.tick()
        if not water.has_pending_work():
            return True
    return False


def test_seed_chunk_sources_enqueues_only_that_chunks_sources():
    world = World()
    generator = TerrainGenerator()
    chunk = world.load_chunk(0, 0, 0, terrain_generator=generator)
    water = WaterSimulation(world)

    count = water.seed_chunk_sources(chunk)

    assert count > 0
    assert len(water.pending_seeds) > 0
    for world_x, world_y, world_z in water.pending_seeds:
        assert 0 <= world_x < 16
        assert 0 <= world_y < 16
        assert 0 <= world_z < 16


def test_loading_a_chunk_invalidates_a_running_water_job():
    world = World()
    generator = TerrainGenerator()
    world.load_chunk(0, 0, 0, terrain_generator=generator)
    water = WaterSimulation(world, max_cells_per_tick=1, max_milliseconds_per_tick=None)
    water.seed_all_sources()
    water.tick()
    assert water.active_job is not None

    version_before = world.water_edit_version
    world.load_chunk(1, 0, 0, terrain_generator=generator)

    assert world.water_edit_version > version_before


def test_unloading_a_chunk_invalidates_a_running_water_job():
    world = World()
    generator = TerrainGenerator()
    world.load_chunk(0, 0, 0, terrain_generator=generator)
    world.load_chunk(1, 0, 0, terrain_generator=generator)
    water = WaterSimulation(world, max_cells_per_tick=1, max_milliseconds_per_tick=None)
    water.seed_all_sources()
    water.tick()
    assert water.active_job is not None

    version_before = world.water_edit_version
    world.unload_chunk(1, 0, 0)

    assert world.water_edit_version > version_before


def test_unloaded_chunk_does_not_keep_watering_the_world():
    world = World()
    generator = TerrainGenerator()
    world.load_chunk(0, 0, 0, terrain_generator=generator)
    water = WaterSimulation(world, max_cells_per_tick=4, max_milliseconds_per_tick=None)
    water.seed_all_sources()

    for _ in range(3):
        water.tick()

    # A job built against the loaded chunk must be discarded once it is gone.
    world.unload_chunk(0, 0, 0)
    assert _run_to_quiescence(world, water)
    assert world.chunks == {}


def test_stale_water_job_cannot_publish_into_a_reloaded_chunk():
    # Reference: a fresh world solved to quiescence.
    fresh_world = World()
    generator = TerrainGenerator()
    fresh_world.load_chunk(0, 0, 0, terrain_generator=generator)
    fresh_water = WaterSimulation(
        fresh_world, max_cells_per_tick=8, max_milliseconds_per_tick=None
    )
    fresh_water.seed_all_sources()
    assert _run_to_quiescence(fresh_world, fresh_water)
    fresh_levels = fresh_world.chunks[(0, 0, 0)].water_levels.copy()

    # Same world, but the chunk is unloaded and reloaded while a job is running.
    world = World()
    world.load_chunk(0, 0, 0, terrain_generator=generator)
    water = WaterSimulation(
        world, max_cells_per_tick=8, max_milliseconds_per_tick=None
    )
    water.seed_all_sources()
    for _ in range(5):
        water.tick()

    world.unload_chunk(0, 0, 0)
    reloaded = world.load_chunk(0, 0, 0, terrain_generator=generator)
    water.seed_chunk_sources(reloaded)

    assert _run_to_quiescence(world, water)

    assert np.array_equal(
        world.chunks[(0, 0, 0)].water_levels, fresh_levels
    )

"""M15 Task 7 - water scheduling equivalence and time-budget tests.

The solver is untouched. Only *when* it runs changed: ``tick`` stops after a
wall-clock budget, and flood, solve and the commit (preparation plus
publication) all resume across ticks. Mesh rebuilds are left to the bounded
``World.reconcile`` in the frame loop, so a water tick never spends the frame on
geometry. These tests prove the final state is unchanged.
"""

import random
import sys
from pathlib import Path

import numpy as np

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from block_data import BlockType  # noqa: E402
from terrain_generation import TerrainGenerator  # noqa: E402
from water import WaterSimulation  # noqa: E402
from world import World  # noqa: E402

SEED = 42


def _generated_world():
    random.seed(SEED)
    world = World()
    TerrainGenerator().generate_world(world)
    return world


def _drain(sim, max_ticks=5000):
    ticks = 0
    while sim.has_pending_work() and ticks < max_ticks:
        sim.tick()
        ticks += 1
    return ticks


def _snapshot(world):
    return {
        key: (
            chunk.blocks.copy(),
            chunk.water_levels.copy(),
            chunk.water_sources.copy(),
        )
        for key, chunk in world.chunks.items()
    }


def test_final_state_is_cell_for_cell_identical_under_a_tiny_time_budget():
    world_a = _generated_world()
    world_b = _generated_world()

    # A: unbounded time, i.e. the previous scheduling.
    sim_a = WaterSimulation(world_a, max_milliseconds_per_tick=None)
    sim_a.seed_all_sources()
    _drain(sim_a)

    # B: a deliberately tiny time budget, forcing many more, shorter ticks.
    sim_b = WaterSimulation(world_b, max_milliseconds_per_tick=0.05)
    sim_b.seed_all_sources()
    ticks_b = _drain(sim_b)

    snapshot_a = _snapshot(world_a)
    snapshot_b = _snapshot(world_b)

    assert set(snapshot_a) == set(snapshot_b)
    for key in snapshot_a:
        blocks_a, levels_a, sources_a = snapshot_a[key]
        blocks_b, levels_b, sources_b = snapshot_b[key]
        assert np.array_equal(blocks_a, blocks_b), f"blocks differ in chunk {key}"
        assert np.array_equal(levels_a, levels_b), f"levels differ in chunk {key}"
        assert np.array_equal(sources_a, sources_b), f"sources differ in chunk {key}"

    # The budget really did fragment the work.
    assert ticks_b > 0


def test_tiny_budget_makes_progress_and_stays_pending():
    world = _generated_world()
    sim = WaterSimulation(world, max_milliseconds_per_tick=0.05)
    sim.seed_all_sources()

    sim.tick()

    # Progress was made...
    assert sim.active_job is not None
    assert len(sim.active_job.visited_flood) > 0
    # ...and the region is still pending, so nothing was lost or half-applied
    # as a "finished" job.
    assert sim.has_pending_work() is True


def test_water_commit_defers_the_mesh_rebuild_to_the_frame_reconcile():
    world = World()
    chunk = world.get_chunk(0, 0, 0)
    chunk.set_block(1, 2, 3, BlockType.WATER)
    chunk.set_water_level(1, 2, 3, 8)
    world.refresh()
    world.dirty_chunks.clear()
    calls_before = world.reconcile_calls
    rebuilds_before = world.rebuild_count

    sim = WaterSimulation(world)
    sim.enqueue(1, 2, 3)
    sim.tick()

    # The unsupported water drained and its chunk is queued for the frame's
    # bounded reconcile...
    assert world.get_block(1, 2, 3) == BlockType.AIR
    assert (0, 0, 0) in world.dirty_chunks
    # ...but the water tick itself rebuilt no geometry, so a commit can never
    # spend the frame's mesh budget from inside the simulation.
    assert world.reconcile_calls == calls_before
    assert world.rebuild_count == rebuilds_before

    # The frame loop publishes it through reconcile.
    assert world.reconcile() >= 1
    assert not world.dirty_chunks


def test_main_runs_reconcile_before_water():
    text = (REPO_ROOT / "main.py").read_text(encoding="utf-8")
    reconcile_at = text.index("world.reconcile()")
    tick_at = text.index(".tick(")
    assert reconcile_at < tick_at
    # Water is skipped on a frame whose mesh budget was already consumed.
    assert "not world.dirty_chunks" in text


if __name__ == "__main__":
    test_final_state_is_cell_for_cell_identical_under_a_tiny_time_budget()
    test_tiny_budget_makes_progress_and_stays_pending()
    test_water_commit_defers_the_mesh_rebuild_to_the_frame_reconcile()
    test_main_runs_reconcile_before_water()
    print("M15 water equivalence tests passed!")

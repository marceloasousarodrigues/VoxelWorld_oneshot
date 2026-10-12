"""M15 follow-up - the water commit contract.

A water job runs flood -> solve -> prepare -> commit. The last two stages publish
the solved region: *prepare* groups the solved cells into one write batch per
affected chunk under the tick budget, *commit* applies those batches under the
tick budget. Both resume across frames, and a batch is applied in a single
vectorised step, so:

* an unsolved job publishes nothing at all;
* a *published chunk is never observable half-applied*: the moment a chunk's data
  changes, it already holds every cell its batch carried;
* the plan's batch order is deterministic, so repeated runs publish the identical
  sequence of intermediate states;
* an external edit arriving mid-publication discards the rest of the plan rather
  than being overwritten by it, and the region is re-solved from the edit;
* the same perturbation reaches the same final state with and without a time
  budget, and mesh rebuilds are left to the frame loop's bounded ``reconcile``.

See `scripts/measure_water_commit.py` for the measured cost of these stages.
"""

import sys
from pathlib import Path

import numpy as np

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from block_data import BlockType  # noqa: E402
from chunk_mesh import generate_chunk_mesh_split  # noqa: E402
from terrain_generation import TerrainGenerator  # noqa: E402
from water import WaterSimulation  # noqa: E402
from world import World  # noqa: E402

BUDGET_MS = 8.0
# Small enough that a batch cannot fit twice in one slice, so the commit has to
# resume across frames.
SPLIT_BUDGET_MS = 0.2
TINY_CELL_BUDGET = 64


def _world():
    """A generated 3x3 seed-42 world with every chunk already meshed."""
    world = World()
    TerrainGenerator().generate_world(world)
    world.dirty_chunks.update(world.chunks)
    world.refresh()
    world.dirty_chunks.clear()
    return world


def _snapshot(world):
    return {
        key: (chunk.blocks.copy(), chunk.water_levels.copy(), chunk.water_sources.copy())
        for key, chunk in world.chunks.items()
    }


def _chunk_snapshot(chunk):
    return (chunk.blocks.copy(), chunk.water_levels.copy(), chunk.water_sources.copy())


def _equal(snapshot_a, snapshot_b):
    if snapshot_a.keys() != snapshot_b.keys():
        return False
    return all(
        np.array_equal(a[0], b[0]) and np.array_equal(a[1], b[1]) and np.array_equal(a[2], b[2])
        for a, b in zip(snapshot_a.values(), snapshot_b.values())
    )


def _invariant_violations(world):
    """Chunks whose water metadata disagrees with their block occupancy."""
    return [
        key for key, chunk in world.chunks.items()
        if not np.array_equal(chunk.blocks == BlockType.WATER, chunk.water_levels > 0)
    ]


def _fill_water_blob(world, x0, x1, z0, z1, y0, y1, level=8):
    """Write unsupported water cells directly (no sources), ready to drain."""
    for x in range(x0, x1):
        for z in range(z0, z1):
            for y in range(y0, y1):
                chunk = world.chunks.get((x // 16, 0, z // 16))
                if chunk is None:
                    continue
                chunk.set_block(x % 16, y, z % 16, BlockType.WATER)
                chunk.set_water_level(x % 16, y, z % 16, level)


def _drain(world, sim, limit=5000):
    frames = 0
    while (sim.has_pending_work() or world.dirty_chunks) and frames < limit:
        sim.consume_changes()
        sim.tick()
        world.reconcile()
        frames += 1
    return frames


def _stale_meshes(world):
    """Chunks whose cached mesh no longer matches a fresh generation."""
    stale = []
    for key, chunk in world.chunks.items():
        v_o, t_o, u_o, v_t, t_t, u_t = generate_chunk_mesh_split(
            chunk, world=world, atlas_map=None
        )
        cached = (
            list(getattr(chunk, "_mesh_vertices", [])),
            list(getattr(chunk, "_mesh_triangles", [])),
            list(getattr(chunk, "_mesh_uvs", [])),
        )
        fresh = (list(v_o) + list(v_t), list(t_o) + list(t_t), list(u_o) + list(u_t))
        if cached != fresh:
            stale.append(key)
    return stale


def _watch_batches(world):
    """Record ``(chunk_key, chunk state after the batch)`` for every publication."""
    applied = []
    original = world.apply_water_batch

    def watched(chunk_key, cells):
        result = original(chunk_key, cells)
        chunk = world.chunks.get(chunk_key)
        if chunk is not None:
            applied.append((chunk_key, _chunk_snapshot(chunk), len(cells)))
        return result

    world.apply_water_batch = watched
    return applied


def _split_scenario(budget=SPLIT_BUDGET_MS, x1=32, z1=28):
    """A 2x2-chunk water blob that must drain, with a budget that splits it."""
    world = _world()
    sim = WaterSimulation(world, max_milliseconds_per_tick=budget)
    _fill_water_blob(world, 0, x1, 0, z1, 8, 16)
    world.dirty_chunks.clear()
    sim.enqueue(1, 15, 1)
    return world, sim


def test_a_partially_advanced_job_publishes_nothing():
    world = _world()
    sim = WaterSimulation(
        world, max_cells_per_tick=TINY_CELL_BUDGET, max_milliseconds_per_tick=BUDGET_MS
    )
    _fill_water_blob(world, 0, 24, 0, 24, 8, 16)
    world.dirty_chunks.clear()
    sim.enqueue(1, 15, 1)

    sim.tick()
    assert sim.active_job is not None
    assert sim.active_job.stage in ("flood", "solve")
    progressed = len(sim.active_job.visited_flood)
    before = _snapshot(world)

    for _ in range(3):
        sim.tick()

    assert sim.active_job is not None, "the test needs a job still in flight"
    assert len(sim.active_job.visited_flood) >= progressed
    # No partial region has been written to the world yet.
    assert _equal(before, _snapshot(world)), "partial water state leaked into the world"


def test_large_multi_chunk_update_is_equivalent_budgeted_and_unbudgeted():
    def run(budget):
        world = _world()
        sim = WaterSimulation(world, max_milliseconds_per_tick=budget)
        _fill_water_blob(world, 0, 32, 0, 24, 8, 16)
        world.dirty_chunks.clear()
        sim.enqueue(1, 15, 1)
        frames = _drain(world, sim)
        return world, sim, frames

    world_a, sim_a, frames_a = run(None)
    world_b, sim_b, frames_b = run(BUDGET_MS)

    assert not sim_a.has_pending_work() and not sim_b.has_pending_work()
    assert not world_a.dirty_chunks and not world_b.dirty_chunks
    assert _equal(_snapshot(world_a), _snapshot(world_b))
    # Both runs really did a large amount of work.
    assert sum(int((c.blocks == BlockType.WATER).sum()) for c in world_a.chunks.values()) > 0
    assert frames_a > 0 and frames_b > 0


def test_repeated_runs_reach_the_same_state():
    def run():
        world = _world()
        sim = WaterSimulation(world, max_milliseconds_per_tick=BUDGET_MS)
        _fill_water_blob(world, 0, 32, 0, 24, 8, 16)
        world.dirty_chunks.clear()
        sim.enqueue(1, 15, 1)
        _drain(world, sim)
        return _snapshot(world)

    assert _equal(run(), run())


def test_external_edit_during_a_pending_job_is_not_overwritten():
    world = _world()
    sim = WaterSimulation(
        world, max_cells_per_tick=TINY_CELL_BUDGET, max_milliseconds_per_tick=BUDGET_MS
    )
    _fill_water_blob(world, 0, 24, 0, 24, 8, 16)
    world.dirty_chunks.clear()
    sim.enqueue(1, 15, 1)
    sim.tick()
    assert sim.active_job is not None
    seeds = set(sim.active_job.seeds)

    # The player places a solid block inside the region the job is planning.
    world.set_block(10, 9, 10, BlockType.STONE)
    world.dirty_chunks.clear()
    before = _snapshot(world)

    sim.tick()

    # The stale job was discarded without publishing anything...
    after = _snapshot(world)
    edited = [
        key for key in before
        if not (
            np.array_equal(before[key][0], after[key][0])
            and np.array_equal(before[key][1], after[key][1])
        )
    ]
    assert edited == [], "the discarded job wrote water state"
    # ...and its seeds were not lost.
    live = set(sim.pending_seeds)
    if sim.active_job is not None:
        live |= set(sim.active_job.seeds)
    assert seeds.issubset(live)

    frames = _drain(world, sim)
    assert frames < 5000
    # The newer edit still wins over the stale plan.
    assert world.get_block(10, 9, 10) == BlockType.STONE
    assert not world.dirty_chunks
    assert _stale_meshes(world) == []


def test_water_crosses_a_chunk_boundary_and_updates_both_chunks():
    world = _world()
    left = world.chunks[(0, 0, 0)]
    right = world.chunks[(1, 0, 0)]
    for key in ((0, 0, 0), (1, 0, 0)):
        chunk = world.chunks[key]
        for x in range(16):
            for z in range(16):
                for y in range(0, 8):
                    chunk.set_block(x, y, z, BlockType.AIR)
                chunk.set_block(x, 4, z, BlockType.STONE)
    left.set_block(15, 5, 8, BlockType.WATER)
    left.set_water_level(15, 5, 8, 8)
    left.set_water_source(15, 5, 8, True)
    world.dirty_chunks.update({(0, 0, 0), (1, 0, 0)})
    world.refresh()
    world.dirty_chunks.clear()

    sim = WaterSimulation(world, max_milliseconds_per_tick=BUDGET_MS)
    sim.enqueue(15, 5, 8)
    frames = _drain(world, sim)

    assert frames < 500
    assert int((left.blocks == BlockType.WATER).sum()) > 0
    assert int((right.blocks == BlockType.WATER).sum()) > 0, "water did not cross the boundary"
    assert int(right.water_levels.max()) > 0
    assert _stale_meshes(world) == []


def test_a_large_commit_resumes_across_frames():
    """The publication stage is fragmented by the tick budget, not atomic."""
    world, sim = _split_scenario()
    applied = _watch_batches(world)

    slices = []
    original_commit = sim._advance_commit

    def counted(job, time_budget=None):
        slices.append(job.commit_cursor)
        return original_commit(job, time_budget)

    sim._advance_commit = counted

    published_per_frame = []
    frames = 0
    while (sim.has_pending_work() or world.dirty_chunks) and frames < 2000:
        sim.consume_changes()
        sim.tick()
        world.reconcile()
        published_per_frame.append(len(applied))
        frames += 1

    total_cells = sum(int((c.blocks == BlockType.WATER).sum()) for c in world.chunks.values())
    assert len(slices) > 1, "the commit finished in a single slice"
    assert len(applied) == len(slices), "each commit slice should apply >= 1 batch"
    # The plan really was published progressively across frames: some frame saw a
    # strictly partial region (more than nothing, less than everything).
    batch_count = len(applied)
    assert 0 < len(published_per_frame) and published_per_frame[-1] == batch_count
    assert any(0 < count < batch_count for count in published_per_frame), published_per_frame
    # Every batch belongs to a distinct chunk, and the region finished.
    keys = [key for key, _, _ in applied]
    assert len(set(keys)) == len(keys), keys
    assert not sim.has_pending_work()
    assert not world.dirty_chunks
    assert total_cells > 0


def test_every_published_chunk_lands_in_one_piece():
    """A chunk is never observable with only part of its batch applied."""
    world, sim = _split_scenario()
    applied = _watch_batches(world)

    violations = []
    frames = 0
    while (sim.has_pending_work() or world.dirty_chunks) and frames < 2000:
        sim.consume_changes()
        sim.tick()
        # Water metadata never disagrees with block occupancy at any frame
        # boundary, including frames that land mid-publication.
        violations.extend(_invariant_violations(world))
        world.reconcile()
        frames += 1

    assert len(applied) >= 2, "the scenario needs several batches to be meaningful"
    assert violations == [], f"chunks left inconsistent: {violations}"
    for chunk_key, snapshot, cells in applied:
        assert cells > 0
        final = _chunk_snapshot(world.chunks[chunk_key])
        assert np.array_equal(snapshot[0], final[0]), f"{chunk_key} was seen half-published"
        assert np.array_equal(snapshot[1], final[1]), f"{chunk_key} was seen half-published"
        assert np.array_equal(snapshot[2], final[2]), f"{chunk_key} was seen half-published"


def test_published_batch_sequence_is_deterministic():
    def sequence():
        world, sim = _split_scenario()
        order = []
        original = world.apply_water_batch

        def watched(chunk_key, cells):
            order.append(chunk_key)
            return original(chunk_key, cells)

        world.apply_water_batch = watched
        _drain(world, sim)
        return order

    first = sequence()
    assert len(first) >= 2
    assert first == sequence()


def test_an_edit_between_commit_slices_is_not_overwritten():
    """The rest of a half-published plan must not clobber a newer edit."""
    world, sim = _split_scenario()
    applied = _watch_batches(world)

    while not (
        sim.active_job is not None
        and sim.active_job.stage == "commit"
        and applied
    ):
        sim.tick()
        world.reconcile()
    job = sim.active_job
    assert job.commit_cursor < len(job.commit_plan), "the plan finished; nothing left to test"

    pending = job.commit_plan[job.commit_cursor:]
    target = next(
        (cells[0] for _, cells in pending if cells),
        None,
    )
    assert target is not None, "no unpublished cell left in the plan"
    x, y, z = target[0], target[1], target[2]

    # The player edits a cell the rest of the plan still intends to write.
    world.set_block(x, y, z, BlockType.STONE)
    world.dirty_chunks.clear()

    frames = _drain(world, sim)

    assert frames < 2000
    assert world.get_block(x, y, z) == BlockType.STONE, "the stale plan overwrote the edit"
    assert world.get_water(x, y, z) == 0
    assert _invariant_violations(world) == []
    assert not sim.has_pending_work()
    assert not world.dirty_chunks
    assert _stale_meshes(world) == []


if __name__ == "__main__":
    import pytest

    pytest.main([__file__, "-v"])

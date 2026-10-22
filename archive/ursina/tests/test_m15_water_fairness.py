"""M15 - scheduler fairness between ``World.reconcile`` and water.

``main.py:update`` prioritises mesh work and skips the water tick whenever the
dirty set is still non-empty after ``reconcile``.  These tests pin the contract
that policy must satisfy:

* water keeps making progress under sustained dirty-chunk activity (it is
  throttled, never starved);
* the dirty set stays bounded while a realistic edit load continues;
* once editing stops both queues drain to empty;
* every chunk mesh left in the world matches a fresh generation of its current
  block data, so no water-driven mesh update is lost to the deferred path.

They deliberately drive the *same* frame policy as ``main.py`` instead of
calling ``reconcile``/``tick`` in isolation, because the interaction between
the two is what is being tested.
"""

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from block_data import BlockType  # noqa: E402
from chunk_mesh import generate_chunk_mesh_split  # noqa: E402
from terrain_generation import TerrainGenerator  # noqa: E402
from water import WaterSimulation  # noqa: E402
from world import World  # noqa: E402

MAX_CONSECUTIVE_SKIPS = 10
BOUNDARY_COLUMN = 15


def _world():
    """A generated 3x3 seed-42 world with every chunk already meshed."""
    world = World()
    TerrainGenerator().generate_world(world)
    # Generation writes blocks directly, so give every chunk a cached mesh to
    # start from; the tests then check that none of them is left stale.
    world.dirty_chunks.update(world.chunks)
    world.refresh()
    world.dirty_chunks.clear()
    return world


def _frame(world, water):
    """One frame of ``main.py:update`` in order. Returns True if water ticked."""
    world.reconcile()
    water.consume_changes()
    if not world.dirty_chunks:
        water.tick()
        return True
    return False


def _boundary_cells(world, chunk_key=(0, 0, 0)):
    """Solid cells in the x=15 column of a chunk (a wall on a chunk seam)."""
    chunk = world.chunks[chunk_key]
    cells = []
    for local_z in range(16):
        for y in range(15, -1, -1):
            if int(chunk.get_block(BOUNDARY_COLUMN, y, local_z)) not in (
                BlockType.AIR,
                BlockType.WATER,
            ):
                cells.append((BOUNDARY_COLUMN, y, local_z))
                break
    return cells


def _sustained_edits(world, water, cells, frames, edits_per_frame=1):
    """Run the frame policy while re-editing boundary cells every frame."""
    ticks = 0
    max_dirty = 0
    max_skip_run = 0
    skip_run = 0
    index = 0
    for _ in range(frames):
        if _frame(world, water):
            ticks += 1
            skip_run = 0
        else:
            skip_run += 1
            max_skip_run = max(max_skip_run, skip_run)
        for _ in range(edits_per_frame):
            local_x, y, local_z = cells[index % len(cells)]
            index += 1
            world.set_block(local_x, y, local_z, BlockType.AIR)
            world.set_block(local_x, y, local_z, BlockType.GRASS)
        max_dirty = max(max_dirty, len(world.dirty_chunks))
    return {
        "ticks": ticks,
        "max_dirty": max_dirty,
        "max_skip_run": max_skip_run,
    }


def _drain(world, water, limit=2000):
    """Run the frame policy without edits until both queues are empty."""
    frames = 0
    while (world.dirty_chunks or water.has_pending_work()) and frames < limit:
        _frame(world, water)
        frames += 1
    return frames


def test_water_keeps_progress_under_sustained_boundary_edits():
    # Mining a wall along a chunk seam dirties the edited chunk *and* its loaded
    # neighbour every frame, which is the heaviest steady load the 8 ms mesh
    # budget cannot fully drain within one frame.
    world = _world()
    water = WaterSimulation(world)
    water.seed_all_sources()
    cells = _boundary_cells(world)
    assert cells

    frames = 60
    result = _sustained_edits(world, water, cells, frames)

    # Water is throttled by mesh work, but it must never be starved.
    assert result["ticks"] > 0
    assert result["ticks"] >= frames // 4, result
    # ...and it must never be blocked for long stretches.
    assert result["max_skip_run"] <= MAX_CONSECUTIVE_SKIPS, result


def test_dirty_set_stays_bounded_under_a_realistic_edit_load():
    # The interaction path fires at most one block change per mouse event, so a
    # single-chunk edit per frame is the shipped worst case.
    world = _world()
    water = WaterSimulation(world)
    water.seed_all_sources()
    cells = _boundary_cells(world)

    result = _sustained_edits(world, water, cells, 60)

    # A bounded queue: the deferred mesh work may lag, but it may not grow.
    assert result["max_dirty"] <= 4, result


def test_queues_drain_to_empty_once_editing_stops():
    world = _world()
    water = WaterSimulation(world)
    water.seed_all_sources()
    cells = _boundary_cells(world)

    _sustained_edits(world, water, cells, 60)
    drained = _drain(world, water)

    assert drained < 2000
    assert world.dirty_chunks == set()
    assert not water.has_pending_work()
    assert water.pending_seeds == {}
    assert water.active_job is None


def test_no_mesh_update_is_lost_by_the_deferred_path():
    # Every chunk's cached mesh must equal a fresh generation of its current
    # block data once the world is quiescent; a dropped reconcile pass would
    # leave a stale mesh behind.
    world = _world()
    water = WaterSimulation(world)
    water.seed_all_sources()
    cells = _boundary_cells(world)

    _sustained_edits(world, water, cells, 30)
    _drain(world, water)

    for key, chunk in world.chunks.items():
        vertices_o, triangles_o, uvs_o, vertices_t, triangles_t, uvs_t = (
            generate_chunk_mesh_split(chunk, world=world, atlas_map=None)
        )
        fresh = (
            list(vertices_o) + list(vertices_t),
            list(triangles_o) + list(triangles_t),
            list(uvs_o) + list(uvs_t),
        )
        cached = (
            list(getattr(chunk, "_mesh_vertices", [])),
            list(getattr(chunk, "_mesh_triangles", [])),
            list(getattr(chunk, "_mesh_uvs", [])),
        )
        assert cached == fresh, f"stale mesh in chunk {key}"


def test_main_update_orders_reconcile_before_water_and_skips_only_on_leftovers():
    # Source contract: reconcile first, then consume, then tick only when no
    # mesh work is still queued.  Reordering or an unconditional tick would
    # either starve water or reintroduce unbounded frame spikes.
    text = (REPO_ROOT / "main.py").read_text(encoding="utf-8")
    reconcile_at = text.index("world.reconcile()")
    consume_at = text.index("water_sim.consume_changes()")
    skip_at = text.index("if not world.dirty_chunks:")
    tick_at = text.index("water_sim.tick()")

    assert reconcile_at < consume_at < skip_at < tick_at


if __name__ == "__main__":
    import pytest

    pytest.main([__file__, "-v"])

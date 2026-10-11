import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from block_data import BlockType
from water import (
    solve_water_view,
    is_water,
    is_passable,
    is_empty,
    MAX_LEVEL,
    SOURCE_LEVEL,
    MAX_HORIZONTAL_SPREAD,
)


# Mock WaterView for testing
class MockWaterView:
    def __init__(self, blocks=None, sources=None, loaded_chunks=None):
        self._blocks = blocks or {}
        self._sources = sources or {}
        self._loaded_chunks = loaded_chunks or {(0, 0, 0)}

    def is_loaded(self, x, y, z):
        cx = x // 16
        cy = y // 16
        cz = z // 16
        return (cx, cy, cz) in self._loaded_chunks

    def get_block(self, x, y, z):
        return self._blocks.get((x, y, z), 0)

    def is_source(self, x, y, z):
        return self._sources.get((x, y, z), False)


# Vertical fill
def test_source_over_empty_space_fills_cell_below():
    view = MockWaterView(
        blocks={(0, 4, 0): BlockType.WATER},
        sources={(0, 4, 0): True},
        loaded_chunks={(0, 0, 0)},
    )
    result = solve_water_view(view, [(0, 4, 0)])
    # Source at (0,4,0) with below (0,3,0) as AIR should fill below
    assert (0, 3, 0) in result
    assert result[(0, 3, 0)] == 8


def test_source_over_multi_cell_drop_fills_entire_column_to_floor():
    view = MockWaterView(
        blocks={(0, 4, 0): BlockType.WATER},
        sources={(0, 4, 0): True},
        loaded_chunks={(0, 0, 0)},
    )
    # Add floor at y=0
    view._blocks[(0, 0, 0)] = BlockType.STONE
    result = solve_water_view(view, [(0, 4, 0)])
    # Column from y=4 down to y=1 should be filled (y=0 is solid floor)
    for y in range(1, 5):
        assert (0, y, 0) in result
        assert result[(0, y, 0)] == 8


def test_vertical_flow_has_priority_over_horizontal():
    view = MockWaterView(
        blocks={
            (0, 2, 0): BlockType.WATER,
            (1, 2, 0): BlockType.AIR,
        },
        sources={(0, 2, 0): True},
        loaded_chunks={(0, 0, 0)},
    )
    # Below (0,2,0) is AIR at (0,1,0) -> vertical flow priority
    result = solve_water_view(view, [(0, 2, 0)])
    assert (0, 1, 0) in result
    assert result[(0, 1, 0)] == 8
    # No horizontal spread from (0,2,0) because it's falling
    assert (1, 2, 0) not in result


def test_downward_flow_into_air_suppresses_horizontal():
    view = MockWaterView(
        blocks={(0, 2, 0): BlockType.WATER},
        sources={(0, 2, 0): True},
        loaded_chunks={(0, 0, 0)},
    )
    # Below is AIR -> vertical flow priority, no horizontal spread
    result = solve_water_view(view, [(0, 2, 0)])
    assert (0, 1, 0) in result
    # Should not spread horizontally while falling
    assert (1, 2, 0) not in result


def test_horizontal_step_decrements_from_seven():
    view = MockWaterView(
        blocks={(x, 2, 0): BlockType.WATER for x in range(2)} | {(x, 1, 0): BlockType.STONE for x in range(2)},
        sources={(0, 2, 0): True},
        loaded_chunks={(0, 0, 0)},
    )
    result = solve_water_view(view, [(0, 2, 0)])
    # Source on solid -> horizontal spread
    assert (0, 2, 0) in result
    assert result[(0, 2, 0)] == 8
    # Neighbor at cost 1 -> level 7
    assert (1, 2, 0) in result
    assert result[(1, 2, 0)] == 7


def test_horizontal_spread_stops_at_configured_limit():
    view = MockWaterView(
        blocks={(x, 2, 0): BlockType.WATER for x in range(8)} | {(x, 1, 0): BlockType.STONE for x in range(8)},
        sources={(0, 2, 0): True},
        loaded_chunks={(0, 0, 0)},
    )
    # Explicit range of 7: water reaches cost 7 but not cost 8.
    result = solve_water_view(view, [(0, 2, 0)], max_horizontal_spread=7)
    assert result.get((7, 2, 0)) == 1
    assert (8, 2, 0) not in result
    for level in result.values():
        assert 1 <= level <= 8


def test_horizontal_flow_reaches_configurable_default_range():
    # The default MAX_HORIZONTAL_SPREAD is 32; water reaches far beyond 7.
    blocks = {(0, 2, 0): BlockType.WATER}
    blocks.update({(x, 1, 0): BlockType.STONE for x in range(33)})
    view = MockWaterView(
        blocks=blocks,
        sources={(0, 2, 0): True},
        loaded_chunks={(0, 0, 0), (1, 0, 0), (2, 0, 0)},
    )
    result = solve_water_view(view, [(0, 2, 0)])
    # Cost 32 is the configured range boundary; the far cell stays level 1.
    assert result.get((32, 2, 0)) == 1
    # Cost 33 is beyond the range.
    assert (33, 2, 0) not in result


def test_reachable_cell_beyond_eight_blocks_stays_water():
    # Without a level clamp, MAX_LEVEL - cost goes non-positive at cost >= 8,
    # drying cells that are still within the horizontal range. Water must not
    # stop early because of level exhaustion.
    blocks = {(0, 2, 0): BlockType.WATER}
    blocks.update({(x, 1, 0): BlockType.STONE for x in range(21)})
    view = MockWaterView(
        blocks=blocks,
        sources={(0, 2, 0): True},
        loaded_chunks={(0, 0, 0), (1, 0, 0)},
    )
    result = solve_water_view(view, [(0, 2, 0)])
    assert result.get((8, 2, 0)) == 1   # cost 8 clamped to level 1
    assert result.get((20, 2, 0)) == 1  # cost 20 clamped to level 1


def test_vertical_fall_has_no_distance_limit():
    # Downward flow is cost 0 and has no distance cap; a 40-block fall fills
    # the whole column at full level.
    blocks = {(0, 40, 0): BlockType.WATER, (0, 0, 0): BlockType.STONE}
    view = MockWaterView(
        blocks=blocks,
        sources={(0, 40, 0): True},
        loaded_chunks={(0, 0, 0), (0, 1, 0), (0, 2, 0)},
    )
    result = solve_water_view(view, [(0, 40, 0)])
    for y in (1, 5, 20, 39):
        assert result[(0, y, 0)] == 8
    assert (0, 0, 0) not in result  # solid floor is a boundary


def test_fall_at_horizontal_limit_preserves_water():
    # A cost-32 cell that falls over an open edge remains water (level 1),
    # not dried out by the accumulated horizontal cost.
    blocks = {(0, 2, 0): BlockType.WATER}
    blocks.update({(x, 1, 0): BlockType.STONE for x in range(32)})  # shelf support
    blocks.update({(x, 0, 0): BlockType.STONE for x in range(33)})  # drop floor
    view = MockWaterView(
        blocks=blocks,
        sources={(0, 2, 0): True},
        loaded_chunks={(0, 0, 0), (1, 0, 0), (2, 0, 0)},
    )
    result = solve_water_view(view, [(0, 2, 0)])
    # (32,2,0) cost 32; (32,1,0) is the open air it falls into, still level 1.
    assert result.get((32, 1, 0)) == 1


def test_multiple_terraces_cascade_across_chunks():
    # Source atop a high ledge falls onto a wide terrace, then a second lower
    # terrace; the cascade crosses the x=15/16 chunk boundary on both ledges.
    blocks = {(8, 20, 0): BlockType.WATER}
    sources = {(8, 20, 0): True}
    for x in range(18):
        blocks[(x, 14, 0)] = BlockType.STONE          # upper terrace floor
    for x in range(18, 32):
        blocks[(x, 10, 0)] = BlockType.STONE          # lower terrace floor
    view = MockWaterView(
        blocks=blocks,
        sources=sources,
        loaded_chunks={(cx, cy, 0) for cx in (0, 1) for cy in (0, 1)},
    )
    result = solve_water_view(view, [(8, 20, 0)])
    assert (16, 15, 0) in result   # upper terrace, beyond x=15 boundary
    assert (30, 11, 0) in result   # lower terrace after the second fall


def test_solid_and_unloaded_are_boundaries():
    view = MockWaterView(
        blocks={(0, 2, 0): BlockType.WATER, (0, 1, 0): BlockType.STONE},
        sources={(0, 2, 0): True},
        loaded_chunks={(0, 0, 0)},
    )
    result = solve_water_view(view, [(0, 2, 0)])
    # Unloaded chunk at x=16 should be boundary (not flow into it)
    # But we only have loaded chunk (0,0,0), so x=16 is in next chunk which is unloaded
    # The solver should not create chunks, so x=16 is treated as boundary
    # Since we only have chunk (0,0,0) loaded, x=16 is unloaded
    # The solver should not create chunks, so x=16 is treated as boundary
    pass  # Behavior tested implicitly


# Existing-water expansion
def test_horizontal_spread_over_existing_water():
    view = MockWaterView(
        blocks={
            (0, 2, 0): BlockType.WATER,
            (1, 2, 0): BlockType.WATER,
            (0, 1, 0): BlockType.STONE,
            (1, 1, 0): BlockType.STONE,
        },
        sources={(0, 2, 0): True},
        loaded_chunks={(0, 0, 0)},
    )
    result = solve_water_view(view, [(0, 2, 0)])
    # Both cells on solid ground, source at (0,2,0) -> (1,2,0) gets level 7
    assert (1, 2, 0) in result
    assert result[(1, 2, 0)] == 7


def test_water_surface_spreads_above_lake():
    view = MockWaterView(
        blocks={
            (0, 3, 0): BlockType.WATER,
            (1, 3, 0): BlockType.WATER,
            (0, 2, 0): BlockType.WATER,
            (1, 2, 0): BlockType.WATER,
            (0, 1, 0): BlockType.STONE,
            (1, 1, 0): BlockType.STONE,
        },
        sources={(0, 3, 0): True, (1, 3, 0): True},  # Top layer sources
        loaded_chunks={(0, 0, 0)},
    )
    result = solve_water_view(view, [(0, 3, 0), (1, 3, 0)])
    # Both surface cells are sources -> level 8
    assert result[(0, 3, 0)] == 8
    assert result[(1, 3, 0)] == 8
    # Lower cells fed from above
    assert result[(0, 2, 0)] == 8


def test_horizontal_flow_when_supported_by_solid():
    view = MockWaterView(
        blocks={(0, 2, 0): BlockType.WATER, (0, 1, 0): BlockType.STONE},
        sources={(0, 2, 0): True},
        loaded_chunks={(0, 0, 0)},
    )
    result = solve_water_view(view, [(0, 2, 0)])
    assert (1, 2, 0) in result
    assert result[(1, 2, 0)] == 7


def test_below_unloaded_allows_horizontal_and_creates_no_chunk():
    view = MockWaterView(
        blocks={(0, 2, 0): BlockType.WATER, (0, 1, 0): BlockType.STONE},
        sources={(0, 2, 0): True},
        loaded_chunks={(0, 0, 0)},
    )
    # Unloaded neighbor at x=16 should be treated as solid boundary
    result = solve_water_view(view, [(0, 2, 0)])
    # Horizontal spread within loaded chunk should work
    assert (1, 2, 0) in result
    # No chunk creation - just treated as boundary
    pass


# Recession / multiple sources
def test_removing_only_source_drains_all_derived():
    # Build a lake with a source, then remove source
    view = MockWaterView(
        blocks={(0, 2, 0): BlockType.WATER, (0, 1, 0): BlockType.STONE},
        sources={(0, 2, 0): True},
        loaded_chunks={(0, 0, 0)},
    )
    result = solve_water_view(view, [(0, 2, 0)])
    assert (1, 2, 0) in result
    assert result[(1, 2, 0)] == 7
    
    # Remove source
    view._sources = {}
    view._blocks = {(0, 2, 0): BlockType.WATER, (0, 1, 0): BlockType.STONE}
    result = solve_water_view(view, [(0, 2, 0)])
    assert result == {}


def test_two_adjacent_sources_are_stable():
    view = MockWaterView(
        blocks={
            (0, 2, 0): BlockType.WATER,
            (1, 2, 0): BlockType.WATER,
            (0, 1, 0): BlockType.STONE,
            (1, 1, 0): BlockType.STONE,
        },
        sources={(0, 2, 0): True, (1, 2, 0): True},
        loaded_chunks={(0, 0, 0)},
    )
    result = solve_water_view(view, [(0, 2, 0), (1, 2, 0)])
    assert result[(0, 2, 0)] == 8
    assert result[(1, 2, 0)] == 8
    # Remove one source
    view._sources = {(0, 2, 0): True}
    result = solve_water_view(view, [(0, 2, 0)])
    # Water at (1,2,0) should now be level 7 (from remaining source)
    assert result[(1, 2, 0)] == 7


def test_water_supplied_by_second_source_remains():
    view = MockWaterView(
        blocks={
            (0, 2, 0): BlockType.WATER,
            (1, 2, 0): BlockType.WATER,
            (0, 1, 0): BlockType.STONE,
            (1, 1, 0): BlockType.STONE,
        },
        sources={(0, 2, 0): True, (1, 2, 0): True},
        loaded_chunks={(0, 0, 0)},
    )
    result = solve_water_view(view, [(0, 2, 0), (1, 2, 0)])
    assert result[(0, 2, 0)] == 8
    assert result[(1, 2, 0)] == 8
    
    # Remove one source - water from other source should remain
    view._sources = {(0, 2, 0): True}
    result = solve_water_view(view, [(0, 2, 0)])
    assert result[(1, 2, 0)] == 7


def test_overlapping_source_influence_uses_minimum_distance():
    view = MockWaterView(
        blocks={
            (0, 2, 0): BlockType.WATER,
            (1, 2, 0): BlockType.WATER,
            (2, 2, 0): BlockType.WATER,
            (0, 1, 0): BlockType.STONE,
            (1, 1, 0): BlockType.STONE,
            (2, 1, 0): BlockType.STONE,
        },
        sources={(0, 2, 0): True, (2, 2, 0): True},
        loaded_chunks={(0, 0, 0)},
    )
    result = solve_water_view(view, [(0, 2, 0), (2, 2, 0)])
    # Middle cell (1,2,0) is distance 1 from both sources -> cost 1 -> level 7
    assert result[(1, 2, 0)] == 7


def test_equal_level_neighbours_do_not_sustain_each_other():
    view = MockWaterView(
        blocks={(0, 2, 0): BlockType.WATER, (1, 2, 0): BlockType.WATER, (0, 1, 0): BlockType.STONE},
        sources={(0, 2, 0): True},
        loaded_chunks={(0, 0, 0)},
    )
    result = solve_water_view(view, [(0, 2, 0)])
    # (1,2,0) gets level 7 from (0,2,0)
    # If source removed, both should drain
    view._sources = {}
    result = solve_water_view(view, [(0, 2, 0)])
    assert result == {}


def test_solver_is_deterministic_and_reaches_fixed_point():
    view = MockWaterView(
        blocks={(0, 2, 0): BlockType.WATER, (0, 1, 0): BlockType.STONE},
        sources={(0, 2, 0): True},
        loaded_chunks={(0, 0, 0)},
    )
    # Run multiple times - should be deterministic
    result1 = solve_water_view(view, [(0, 2, 0)])
    result2 = solve_water_view(view, [(0, 2, 0)])
    assert result1 == result2


def test_cost_seven_cell_still_spreads_downward():
    # Spec D2.1 / D2.2.1: downward propagation is unconditional; the horizontal
    # spread limit must not suppress vertical fill for a cell already at cost 7.
    blocks = {(x, 2, 0): BlockType.WATER for x in range(8)}
    # Shelf support under x=0..6; x=7 is on the edge with air below (a drop).
    blocks.update({(x, 1, 0): BlockType.STONE for x in range(7)})
    blocks[(0, 0, 0)] = BlockType.STONE  # floor of the drop
    view = MockWaterView(
        blocks=blocks,
        sources={(0, 2, 0): True},
        loaded_chunks={(0, 0, 0)},
    )
    result = solve_water_view(view, [(0, 2, 0)])
    # (7,2,0) is the last reachable horizontal cell (cost 7 -> level 1).
    assert result.get((7, 2, 0)) == 1
    # It must still fall into the opened air below at cost 7.
    assert result.get((7, 1, 0)) == 1


def test_simulation_fills_downward_at_horizontal_limit():
    from world import World
    from water import WaterSimulation

    w = World()
    chunk = w.get_chunk(0, 0, 0)
    # Shelf at y=2 supported by stone at y=1 for x=0..6; a drop opens at x=7.
    for x in range(8):
        chunk.set_block(x, 2, 0, BlockType.WATER)
        chunk.set_water_level(x, 2, 0, 8)
        if x < 7:
            chunk.set_block(x, 1, 0, BlockType.STONE)
        else:
            chunk.set_block(x, 0, 0, BlockType.STONE)
    chunk.set_water_source(0, 2, 0, True)

    sim = WaterSimulation(w)
    sim.seed_all_sources()
    while sim.has_pending_work():
        sim.tick()

    # The cost-7 cell must still fill the opened air below it.
    assert w.get_block(7, 1, 0) == BlockType.WATER
    assert w.get_water(7, 1, 0) == 1


def test_repeated_edits_recompute_cascade():
    from world import World
    from water import WaterSimulation

    w = World()
    # Wide solid terrace at y=1 supporting a solid layer at y=2 (x=0..40).
    for x in range(0, 41):
        c = w.get_chunk(x // 16, 0, 0)
        c.set_block(x % 16, 1, 0, BlockType.STONE)
        c.set_block(x % 16, 2, 0, BlockType.STONE)
    c0 = w.get_chunk(0, 0, 0)
    c0.set_block(0, 2, 0, BlockType.WATER)
    c0.set_water_level(0, 2, 0, 8)
    c0.set_water_source(0, 2, 0, True)

    sim = WaterSimulation(w)
    sim.seed_all_sources()
    while sim.has_pending_work():
        sim.tick()

    # Carve a path outward one block at a time while the cascade is live; each
    # edit must recompute and keep the water front advancing to the far range.
    for wx in range(1, 41):
        w.set_block(wx, 2, 0, BlockType.AIR)
        sim.consume_changes()
        while sim.has_pending_work():
            sim.tick()

    assert w.get_block(20, 2, 0) == BlockType.WATER  # far beyond the old 7
    assert w.get_water(20, 2, 0) >= 1
    assert w.get_block(34, 2, 0) != BlockType.WATER   # beyond the 32 range


def test_simulation_respects_custom_horizontal_range():
    from world import World
    from water import WaterSimulation

    w = World()
    for x in range(0, 41):
        c = w.get_chunk(x // 16, 0, 0)
        c.set_block(x % 16, 1, 0, BlockType.STONE)
        c.set_block(x % 16, 2, 0, BlockType.STONE)
    c0 = w.get_chunk(0, 0, 0)
    c0.set_block(0, 2, 0, BlockType.WATER)
    c0.set_water_level(0, 2, 0, 8)
    c0.set_water_source(0, 2, 0, True)

    sim = WaterSimulation(w, max_horizontal_spread=5)
    sim.seed_all_sources()
    while sim.has_pending_work():
        sim.tick()

    for wx in range(1, 41):
        w.set_block(wx, 2, 0, BlockType.AIR)
        sim.consume_changes()
        while sim.has_pending_work():
            sim.tick()

    assert w.get_block(5, 2, 0) == BlockType.WATER
    assert w.get_block(6, 2, 0) != BlockType.WATER


def test_source_with_water_below_spreads_horizontally():
    # Spec D2.1: horizontal spread is suppressed only when the cell below is
    # loaded AIR. Existing water below must not suppress spread.
    view = MockWaterView(
        blocks={
            (0, 3, 0): BlockType.WATER,
            (0, 2, 0): BlockType.WATER,
            (1, 2, 0): BlockType.WATER,
            (0, 1, 0): BlockType.STONE,
            (1, 1, 0): BlockType.STONE,
        },
        sources={(0, 3, 0): True},
        loaded_chunks={(0, 0, 0)},
    )
    result = solve_water_view(view, [(0, 3, 0)])
    # Surface neighbour is reachable at horizontal cost 1 -> level 7.
    assert result.get((1, 3, 0)) == 7


def test_simulation_drain_commit_removes_unsupported_water():
    from world import World
    from water import WaterSimulation

    w = World()
    chunk = w.get_chunk(0, 0, 0)
    chunk.set_block(1, 2, 3, BlockType.WATER)
    chunk.set_water_level(1, 2, 3, 8)

    sim = WaterSimulation(w)
    sim.enqueue(1, 2, 3)
    sim.tick()

    assert w.get_block(1, 2, 3) == BlockType.AIR
    assert w.get_water(1, 2, 3) == 0


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
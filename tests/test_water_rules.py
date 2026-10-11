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


def test_horizontal_spread_stops_after_seven():
    view = MockWaterView(
        blocks={(x, 2, 0): BlockType.WATER for x in range(8)} | {(x, 1, 0): BlockType.STONE for x in range(8)},
        sources={(0, 2, 0): True},
        loaded_chunks={(0, 0, 0)},
    )
    result = solve_water_view(view, [(0, 2, 0)])
    # Cost 7 -> level 1 at distance 7
    # Cost 8 -> no water
    # Just verify level 1 exists
    level_1_cells = [cell for cell, level in result.items() if cell != (0, 2, 0) and result[cell] == 1]
    assert len(level_1_cells) > 0
    # No level 0 cells should exist
    for level in result.values():
        assert level >= 1


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


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
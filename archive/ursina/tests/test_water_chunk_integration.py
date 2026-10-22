import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from block_data import BlockType
from chunk import Chunk
from world import World
from terrain_generation import TerrainGenerator
from water import WaterSimulation


# ---------------------------------------------------------------------------
# Chunk water layer
# ---------------------------------------------------------------------------

def test_chunk_water_layer_defaults_and_roundtrip():
    c = Chunk(0, 0, 0)
    assert c.get_water_level(1, 2, 3) == 0
    assert c.get_water_source(1, 2, 3) is False

    c.set_water_level(1, 2, 3, 5)
    c.set_water_source(1, 2, 3, True)

    assert c.get_water_level(1, 2, 3) == 5
    assert c.get_water_source(1, 2, 3) is True


def test_chunk_water_level_clamped_and_clear_water():
    c = Chunk(0, 0, 0)

    c.set_water_level(0, 0, 0, 99)
    assert c.get_water_level(0, 0, 0) == 8

    c.set_water_level(0, 0, 0, -3)
    assert c.get_water_level(0, 0, 0) == 0

    c.set_water_level(0, 0, 0, 4)
    c.set_water_source(0, 0, 0, True)
    c.clear_water(0, 0, 0)

    assert c.get_water_level(0, 0, 0) == 0
    assert c.get_water_source(0, 0, 0) is False


# ---------------------------------------------------------------------------
# World water interfaces
# ---------------------------------------------------------------------------

def test_world_exposes_changed_blocks_and_water_accessors():
    w = World()
    assert w.changed_blocks == set()
    assert w.is_loaded(0, 0, 0) is False

    w.get_chunk(0, 0, 0)

    assert w.is_loaded(0, 0, 0) is True
    assert w.get_water(0, 0, 0) == 0
    assert w.is_source(0, 0, 0) is False
    assert hasattr(w, "set_water")


def test_set_water_on_unloaded_chunk_is_noop():
    w = World()
    assert w.set_water(0, 0, 0, 5) is False
    assert (0, 0, 0) not in w.chunks


def test_set_water_below_y0_is_noop():
    w = World()
    w.get_chunk(0, -1, 0)
    assert w.set_water(0, -1, 0, 5) is False
    assert w.get_block(0, -1, 0) == BlockType.AIR


def test_set_water_creates_water_without_edit_log_or_version_bump():
    w = World()
    w.get_chunk(0, 0, 0)
    version_before = w.water_edit_version

    changed = w.set_water(1, 2, 3, 8, source=True)

    assert changed is True
    assert w.get_block(1, 2, 3) == BlockType.WATER
    assert w.get_water(1, 2, 3) == 8
    assert w.is_source(1, 2, 3) is True
    assert w.changed_blocks == set()
    assert w.water_edit_version == version_before


def test_set_water_occupancy_change_marks_chunk_dirty():
    w = World()
    w.get_chunk(0, 0, 0)
    w.dirty_chunks.clear()

    changed = w.set_water(1, 2, 3, 8)

    assert changed is True
    assert (0, 0, 0) in w.dirty_chunks


def test_set_water_level_only_change_marks_nothing_dirty():
    w = World()
    w.get_chunk(0, 0, 0)
    w.set_water(1, 2, 3, 8)
    w.refresh()
    w.dirty_chunks.clear()

    changed = w.set_water(1, 2, 3, 4)

    assert changed is False
    assert w.dirty_chunks == set()
    assert w.get_water(1, 2, 3) == 4


def test_set_water_drain_clears_occupancy_and_source():
    w = World()
    w.get_chunk(0, 0, 0)
    w.set_water(1, 2, 3, 8, source=True)

    changed = w.set_water(1, 2, 3, 0)

    assert changed is True
    assert w.get_block(1, 2, 3) == BlockType.AIR
    assert w.get_water(1, 2, 3) == 0
    assert w.is_source(1, 2, 3) is False


# ---------------------------------------------------------------------------
# set_block metadata cleanup and invalidation
# ---------------------------------------------------------------------------

def test_set_block_records_edit_and_invalidates():
    w = World()
    w.set_block(4, 4, 4, BlockType.STONE)

    assert (4, 4, 4) in w.changed_blocks
    assert w.water_edit_version == 1


def test_set_block_clears_water_metadata():
    w = World()
    w.get_chunk(0, 0, 0)
    w.set_water(1, 2, 3, 8, source=True)

    w.set_block(1, 2, 3, BlockType.STONE)

    chunk = w.chunks[(0, 0, 0)]
    assert chunk.get_water_level(1, 2, 3) == 0
    assert chunk.get_water_source(1, 2, 3) is False


def test_set_block_no_op_does_not_record_or_increment():
    w = World()
    w.get_chunk(0, 0, 0)

    w.set_block(1, 2, 3, BlockType.AIR)

    assert w.changed_blocks == set()
    assert w.water_edit_version == 0


# ---------------------------------------------------------------------------
# Lake generation and startup
# ---------------------------------------------------------------------------

def test_lake_top_layer_is_sources_and_lower_is_not():
    w = World()
    TerrainGenerator().generate_world(w)

    water = 0
    top_sources = 0
    lower_sources = 0
    for chunk in w.chunks.values():
        for x in range(Chunk.SIZE_X):
            for y in range(Chunk.SIZE_Y):
                for z in range(Chunk.SIZE_Z):
                    if chunk.get_block(x, y, z) == BlockType.WATER:
                        water += 1
                        if chunk.get_water_source(x, y, z):
                            if y == 4:
                                top_sources += 1
                            else:
                                lower_sources += 1

    assert water > 0
    assert top_sources > 0
    assert lower_sources == 0


# ---------------------------------------------------------------------------
# Main wiring
# ---------------------------------------------------------------------------

def test_main_wires_water_simulation():
    text = (REPO_ROOT / "main.py").read_text(encoding="utf-8")
    assert "WaterSimulation" in text
    assert "seed_all_sources" in text
    assert ".tick(" in text
    assert "world=world" in text


# ---------------------------------------------------------------------------
# Headless simulation smoke
# ---------------------------------------------------------------------------

def _drain_simulation(sim, max_ticks=1000):
    ticks = 0
    while sim.has_pending_work() and ticks < max_ticks:
        sim.tick()
        ticks += 1
    return ticks


def test_headless_water_simulation_smoke():
    w = World()
    TerrainGenerator().generate_world(w)
    before = sum(int((c.blocks == BlockType.WATER).sum()) for c in w.chunks.values())

    sim = WaterSimulation(w)
    sim.seed_all_sources()
    _drain_simulation(sim)

    after = sum(int((c.blocks == BlockType.WATER).sum()) for c in w.chunks.values())
    assert before > 0
    # A stable lake must not lose water.
    assert after == before


def test_external_edit_during_active_job_invalidates_without_losing_seeds():
    w = World()
    w.get_chunk(0, 0, 0)
    w.set_water(0, 3, 0, 8, source=True)

    sim = WaterSimulation(w, max_cells_per_tick=1)
    sim.seed_all_sources()

    sim.tick()
    assert sim.active_job is not None

    # External edit invalidates the in-flight job.
    w.set_block(9, 9, 9, BlockType.STONE)
    sim.tick()

    live_seeds = set(sim.pending_seeds_set)
    if sim.active_job is not None:
        live_seeds |= set(sim.active_job.seeds)
    assert (0, 3, 0) in live_seeds


def test_consume_changes_transfers_edit_log_to_pending():
    w = World()
    w.get_chunk(0, 0, 0)
    w.set_block(5, 5, 5, BlockType.STONE)

    sim = WaterSimulation(w)
    sim.consume_changes()

    assert w.changed_blocks == set()
    assert (5, 5, 5) in sim.pending_seeds_set


if __name__ == "__main__":
    pytest.main([__file__, "-v"])

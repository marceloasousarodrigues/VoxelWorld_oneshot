import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

import random

import numpy as np

from world import World
from terrain_generation import TerrainGenerator
from block_data import BlockType
import water
from water import WaterSimulation
import vegetation

SEED = 42
STEPS = 200


def test_placing_block_clears_decoration_in_cell():
    w = World()
    c = w.get_chunk(0, 0, 0)
    c.set_block(1, 1, 1, BlockType.GRASS)
    c.set_decoration(1, 2, 1, 3)
    w.set_block(1, 2, 1, BlockType.STONE)
    assert c.get_decoration(1, 2, 1) == 0


def test_removing_support_clears_decoration_above():
    w = World()
    c = w.get_chunk(0, 0, 0)
    c.set_block(1, 1, 1, BlockType.GRASS)
    c.set_decoration(1, 2, 1, 3)
    w.set_block(1, 1, 1, BlockType.AIR)
    assert c.get_decoration(1, 2, 1) == 0


def test_set_block_still_marks_dirty_and_records_edit():
    w = World()
    w.get_chunk(0, 0, 0)
    w.set_block(1, 1, 1, BlockType.STONE)
    assert (0, 0, 0) in w.dirty_chunks
    assert (1, 1, 1) in w.changed_blocks


def _build(with_vegetation):
    # Spec 5.2: one helper builds both worlds; the only variable is the flag.
    world = World()
    generator = TerrainGenerator()
    generator.seed = SEED
    random.seed(SEED)
    generator._generate_height_map_terrain(world)
    if with_vegetation:
        vegetation.generate_vegetation(world, SEED)
    return world


def _water_cells(world):
    return sum(int((c.blocks == BlockType.WATER).sum()) for c in world.chunks.values())


def _water_level_total(world):
    return sum(int(c.water_levels.sum()) for c in world.chunks.values())


def _water_source_count(world):
    return sum(int(c.water_sources.sum()) for c in world.chunks.values())


def _simulate(world):
    # Identical on both sides: seed all sources once, then a fixed number of ticks.
    sim = WaterSimulation(world)
    sim.seed_all_sources()
    for _ in range(STEPS):
        sim.consume_changes()
        sim.tick()
    return sim


def test_vegetation_is_added():
    world = _build(True)
    decor = sum(int((c.decorations > 0).sum()) for c in world.chunks.values())
    trees = sum(int((c.blocks == BlockType.OAK_LOG).sum()) for c in world.chunks.values())
    assert decor > 0
    assert trees > 0


def test_water_setup_identical_before_simulation():
    # Same seed and same terrain function, so nothing water-related may differ.
    base = _build(False)
    veg = _build(True)
    assert _water_cells(veg) == _water_cells(base) > 0
    assert _water_level_total(veg) == _water_level_total(base)
    assert _water_source_count(veg) == _water_source_count(base) > 0


def test_no_vegetation_on_water_cells():
    world = _build(True)
    for c in world.chunks.values():
        water_mask = c.blocks == BlockType.WATER
        assert not (c.decorations[water_mask] > 0).any()
        tree_mask = np.isin(c.blocks, (BlockType.OAK_LOG, BlockType.OAK_LEAVES))
        assert not (tree_mask & water_mask).any()


def test_passability_only_narrows():
    base = _build(False)
    veg = _build(True)
    # The predicate itself is unchanged for pre-existing block types.
    assert water.is_passable(BlockType.AIR) is True
    assert water.is_passable(BlockType.WATER) is True
    for block in (BlockType.GRASS, BlockType.DIRT, BlockType.STONE, BlockType.SAND):
        assert water.is_passable(block) is False
    assert water.is_passable(BlockType.OAK_LOG) is False
    assert water.is_passable(BlockType.OAK_LEAVES) is False
    # Cell-wise, passability may only change passable -> non-passable.
    assert set(base.chunks) == set(veg.chunks)
    passable = (BlockType.AIR, BlockType.WATER)
    for key in base.chunks:
        before = base.chunks[key].blocks
        after = veg.chunks[key].blocks
        became_passable = (~np.isin(before, passable)) & np.isin(after, passable)
        assert not became_passable.any(), key


def test_water_identical_after_simulation():
    # Equivalent conditions: equal seed, initial state, STEPS and budget.
    base = _simulate(_build(False))
    veg = _simulate(_build(True))
    assert _water_cells(veg.world) == _water_cells(base.world)
    assert _water_level_total(veg.world) == _water_level_total(base.world)
    assert _water_source_count(veg.world) == _water_source_count(base.world)


def test_generate_world_runs_vegetation_and_leaves_water_unchanged():
    # The wiring itself: a normal world generation must produce vegetation while
    # leaving the terrain and water layout byte-for-byte as it was.
    wired = World()
    generator = TerrainGenerator()
    generator.seed = SEED
    random.seed(SEED)
    generator.generate_world(wired)

    assert sum(int((c.decorations > 0).sum()) for c in wired.chunks.values()) > 0
    assert sum(int((c.blocks == BlockType.OAK_LOG).sum()) for c in wired.chunks.values()) > 0

    terrain_only = _build(False)
    assert set(wired.chunks) == set(terrain_only.chunks)
    assert _water_cells(wired) == _water_cells(terrain_only)
    assert _water_level_total(wired) == _water_level_total(terrain_only)
    assert _water_source_count(wired) == _water_source_count(terrain_only)
    total_added = 0
    for key in terrain_only.chunks:
        before = terrain_only.chunks[key].blocks
        after = wired.chunks[key].blocks
        changed = before != after
        gains_a_tree = np.isin(after, (BlockType.OAK_LOG, BlockType.OAK_LEAVES))
        # Vegetation only ever adds tree blocks: no terrain cell is cleared or
        # replaced with a different terrain block.
        assert (changed <= gains_a_tree).all(), key
        total_added += int(changed.sum())
    assert total_added > 0

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

import random

import numpy as np

from chunk import Chunk
from chunk_mesh import generate_chunk_mesh_split
from chunk_entity import create_chunk_entity
from player import VoxelPlayer
from raycast import raycast
from world import World
from terrain_generation import TerrainGenerator
from block_data import BlockType, is_block_solid, get_block_face_textures
from texture_config import load_atlas_map
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


def test_raycast_passes_through_tuft_cells():
    w = World()
    c = w.get_chunk(0, 0, 0)
    c.set_block(5, 0, 0, BlockType.STONE)
    c.set_decoration(3, 0, 0, 1)  # tuft in the ray path, cell stays AIR
    hit = raycast((0.5, 0.5, 0.5), (1, 0, 0), w, max_range=6)
    assert hit is not None
    assert hit["position"] == (5, 0, 0)


def test_raycast_hits_a_trunk_like_any_solid_block():
    w = World()
    c = w.get_chunk(0, 0, 0)
    c.set_block(4, 0, 0, BlockType.OAK_LEAVES)
    hit = raycast((0.5, 0.5, 0.5), (1, 0, 0), w, max_range=6)
    assert hit is not None
    assert hit["position"] == (4, 0, 0)
    assert hit["block_type"] == int(BlockType.OAK_LEAVES)


def test_tuft_cells_are_not_solid_for_water():
    assert water.is_passable(BlockType.AIR) is True
    assert water.is_passable(BlockType.WATER) is True
    assert water.is_passable(BlockType.GRASS) is False
    # decoration layer does not change block types


def test_passability_predicate_unchanged_for_every_block_type():
    # Spec 5.2 assertion 3: the predicate is unchanged for pre-existing types and
    # the two new solid tree types are non-passable. The set check also covers any
    # block type added later.
    assert water.is_passable(BlockType.AIR) is True
    assert water.is_passable(BlockType.WATER) is True
    for block in (BlockType.GRASS, BlockType.DIRT, BlockType.STONE,
                  BlockType.SAND, BlockType.OAK_LOG, BlockType.OAK_LEAVES):
        assert water.is_passable(block) is False
    assert {bt for bt in BlockType if water.is_passable(bt)} == {
        BlockType.AIR,
        BlockType.WATER,
    }


def test_decorations_add_geometry_only_to_the_opaque_mesh():
    # One combined opaque mesh plus the existing water child per chunk: a tuft
    # adds exactly two quads to the opaque lists and nothing to the water child.
    chunk = Chunk(0, 0, 0)
    chunk.set_block(0, 0, 0, BlockType.STONE)
    chunk.set_block(1, 0, 0, BlockType.WATER)
    chunk.set_decoration(2, 1, 0, 1)

    control = Chunk(0, 0, 0)
    control.set_block(0, 0, 0, BlockType.STONE)
    control.set_block(1, 0, 0, BlockType.WATER)

    vo, to, uo, vt, tt, ut = generate_chunk_mesh_split(chunk)
    cv, ct, cu, cvt, ctt, cut = generate_chunk_mesh_split(control)

    assert len(to) == len(ct) + 12  # one tuft = two quads of two triangles
    assert len(vo) == len(cv) + 24
    assert len(uo) == len(cu) + 8
    assert len(vt) == len(cvt)
    assert len(tt) == len(ctt)
    assert len(ut) == len(cut)

    entity = create_chunk_entity(chunk, (0, 0, 0))
    assert entity is not None
    assert chunk.entity is entity
    assert chunk.entity_transparent is not None
    assert chunk.entity_transparent.parent is entity


def test_breaking_a_tree_block_clears_it_and_regenerates_the_chunk_mesh():
    # Tree blocks are ordinary solid blocks, so breaking one must go through the
    # normal edit path: the block is removed and the chunk mesh is regenerated
    # without its geometry.
    world = World()
    chunk = world.get_chunk(0, 0, 0)
    world.set_block(2, 0, 0, BlockType.OAK_LOG)
    world.refresh()
    chunk.refresh()
    before = len(chunk._mesh_vertices)
    assert before > 0, "the trunk produced no geometry"

    player = VoxelPlayer(world, spawn_position=(8, 10, 8))
    player.interaction_range = 6.0
    player.get_interaction_ray = lambda: ((0.5, 0.5, 0.5), (1, 0, 0))

    assert player.break_block() == (2, 0, 0)
    assert world.get_block(2, 0, 0) == BlockType.AIR
    # break_block refreshes the world, so the edit is consumed by that refresh
    # and the chunk now meshes to nothing.
    assert world.dirty_chunks == set()
    assert len(chunk._mesh_vertices) == 0


def test_tree_blocks_collide_and_tuft_cells_do_not():
    # Collision and raycast both resolve through is_block_solid and the block
    # grid, so a trunk or canopy block collides like any other solid block while a
    # tuft — decoration only, block left as AIR — can never collide.
    world = World()
    chunk = world.get_chunk(0, 0, 0)
    chunk.set_block(0, 0, 0, BlockType.OAK_LOG)
    chunk.set_block(1, 0, 0, BlockType.OAK_LEAVES)
    chunk.set_decoration(2, 0, 0, 1)

    assert is_block_solid(world.get_block(0, 0, 0)) is True
    assert is_block_solid(world.get_block(1, 0, 0)) is True
    assert world.get_block(2, 0, 0) == BlockType.AIR
    assert is_block_solid(world.get_block(2, 0, 0)) is False
    # A ray straight through the tuft cell meets nothing at all.
    assert raycast((2.5, 0.5, 0.5), (0, 0, 1), world, max_range=3) is None


def test_leaf_and_log_faces_use_their_own_atlas_tiles():
    # Foliage cubes cull and texture exactly like existing solid blocks: an
    # isolated block emits all six faces and every face UV lies inside that
    # block's own tile, with no fallback to another texture.
    atlas = load_atlas_map()
    assert atlas is not None

    def rect(tile):
        return (tile["u0"], tile["u1"], 1 - tile["v1"], 1 - tile["v0"])

    for block, suffixes in (
        (BlockType.OAK_LEAVES, ("default_leaves.png",)),
        (BlockType.OAK_LOG, ("default_tree.png", "default_tree_top.png")),
    ):
        chunk = Chunk(0, 0, 0)
        chunk.set_block(0, 0, 0, block)
        vo, to, uo, vt, tt, ut = generate_chunk_mesh_split(chunk, atlas_map=atlas)

        assert len(to) == 6 * 6, f"{block} did not emit all six cube faces"
        assert len(uo) == 6 * 4
        assert tt == [] and vt == [], f"{block} leaked into the transparent mesh"

        allowed = [
            rect(tile)
            for path, tile in atlas["tiles"].items()
            if path.endswith(suffixes)
        ]
        assert allowed, f"no atlas tile found for {block}"
        for (u, v) in uo:
            assert any(
                u0 - 1e-9 <= u <= u1 + 1e-9 and v0 - 1e-9 <= v <= v1 + 1e-9
                for (u0, u1, v0, v1) in allowed
            ), f"{block} face UV {(u, v)} is outside its own tile(s) {allowed}"

        # The tile really is the manifest's per-face source for this block.
        faces = get_block_face_textures(block)
        assert faces["side"] in atlas["tiles"]


def test_placing_a_block_into_a_tuft_cell_clears_the_tuft():
    world = World()
    chunk = world.get_chunk(0, 0, 0)
    world.set_block(2, 0, 0, BlockType.STONE)
    chunk.set_decoration(1, 0, 0, 2)  # a tuft occupies the placement target

    player = VoxelPlayer(world, spawn_position=(8, 10, 8))
    player.interaction_range = 6.0
    player.inventory.add_item(BlockType.DIRT, 64)
    player.get_interaction_ray = lambda: ((0.5, 0.5, 0.5), (1, 0, 0))

    assert player.place_block() == (1, 0, 0)
    assert world.get_block(1, 0, 0) == BlockType.DIRT
    assert chunk.get_decoration(1, 0, 0) == 0

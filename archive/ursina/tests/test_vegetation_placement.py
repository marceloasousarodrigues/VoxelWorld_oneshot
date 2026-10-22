import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

import numpy

from block_data import BlockType
from chunk import Chunk
from terrain_generation import TerrainGenerator, surface_height, in_lake, LAKE_LEVEL
from world import World
import vegetation


def test_decoration_defaults_and_roundtrip():
    c = Chunk(0, 0, 0)
    assert c.get_decoration(1, 2, 3) == 0

    c.set_decoration(1, 2, 3, 4)

    assert c.get_decoration(1, 2, 3) == 4


def test_clear_decoration_resets_to_none():
    c = Chunk(0, 0, 0)
    c.set_decoration(0, 0, 0, 2)

    c.clear_decoration(0, 0, 0)

    assert c.get_decoration(0, 0, 0) == 0


def test_decoration_layer_does_not_touch_blocks():
    c = Chunk(0, 0, 0)

    c.set_decoration(5, 5, 5, 3)

    assert c.get_block(5, 5, 5) == 0  # AIR unchanged


def _fresh_chunk(cx=0, cz=0, seed=42):
    c = Chunk(cx, 0, cz)
    # minimal terrain: fill the grass surface via the same pure function
    for x in range(16):
        for z in range(16):
            gx, gz = cx * 16 + x, cz * 16 + z
            h = surface_height(seed, gx, gz)
            for y in range(h + 1):
                c.set_block(x, y, z, 1 if y == h else 2)  # GRASS / DIRT
    return c


def test_tufts_only_on_exposed_grass():
    c = _fresh_chunk()
    vegetation.generate_vegetation_for_chunk(c, 42)
    for x in range(16):
        for z in range(16):
            gx, gz = x, z
            if in_lake(gx, gz):
                continue
            y = surface_height(42, gx, gz) + 1
            if y > 15:
                continue
            v = c.get_decoration(x, y, z)
            if v:
                assert c.get_block(x, y - 1, z) == 1  # GRASS support
                assert c.get_block(x, y, z) == 0     # AIR above


def test_no_tufts_above_y15_or_in_lake():
    c = _fresh_chunk()
    vegetation.generate_vegetation_for_chunk(c, 42)
    for x in range(16):
        for y in range(16):
            for z in range(16):
                if c.get_decoration(x, y, z):
                    assert y <= 15
                    assert not in_lake(x, z)


def test_tuft_density_is_reasonable():
    placed = total = 0
    for cx in range(-2, 3):
        c = _fresh_chunk(cx, 0)
        vegetation.generate_vegetation_for_chunk(c, 42)
        for x in range(16):
            for z in range(16):
                gx = cx * 16 + x
                y = surface_height(42, gx, z) + 1
                if in_lake(gx, z) or y > 15:
                    continue
                total += 1
                if c.get_decoration(x, y, z):
                    placed += 1
    assert total > 0
    assert 0.15 < placed / total < 0.5


def test_no_decoration_sits_inside_a_block_in_a_real_world():
    # A real generated world (terrain + trees) must never carry a tuft inside a
    # solid block, over the lake, or floating without a grass support. This is the
    # invariant that the AIR guard in the placement rule protects.
    world = World()
    TerrainGenerator().generate_world(world)
    vegetation.generate_vegetation(world, 42)

    checked = 0
    for chunk in world.chunks.values():
        for x in range(chunk.SIZE_X):
            for y in range(chunk.SIZE_Y):
                for z in range(chunk.SIZE_Z):
                    if not chunk.get_decoration(x, y, z):
                        continue
                    checked += 1
                    where = (chunk.chunk_x, chunk.chunk_y, chunk.chunk_z, x, y, z)
                    assert chunk.get_block(x, y, z) == BlockType.AIR, (
                        f"tuft inside a solid block at {where}"
                    )
                    assert chunk.get_block(x, y - 1, z) == BlockType.GRASS, (
                        f"tuft without grass support at {where}"
                    )
                    assert not in_lake(
                        chunk.chunk_x * chunk.SIZE_X + x,
                        chunk.chunk_z * chunk.SIZE_Z + z,
                    ), f"tuft over the lake at {where}"
    assert checked > 0, "no decorations were generated, so nothing was verified"


def test_vegetation_is_confined_to_the_ground_chunk_layer():
    # Terrain only exists in chunk_y == 0, so no other layer may receive
    # vegetation. Without this guard a chunk_y == 1 chunk would receive tree
    # blocks at the same absolute Y coordinates as a ground chunk.
    for chunk_y in (1, 2, -1):
        chunk = Chunk(0, chunk_y, 0)
        for x in range(chunk.SIZE_X):
            for z in range(chunk.SIZE_Z):
                for y in range(chunk.SIZE_Y):
                    chunk.set_block(
                        x, y, z,
                        BlockType.STONE if y < 8 else BlockType.AIR,
                    )
        before = chunk.blocks.copy()

        vegetation.generate_vegetation_for_chunk(chunk, 42)

        assert numpy.array_equal(chunk.blocks, before), f"chunk_y={chunk_y} was modified"
        assert int(chunk.decorations.sum()) == 0, f"chunk_y={chunk_y} got decorations"


def test_a_tree_clears_any_stale_decoration_in_its_cells():
    # Regeneration (or a second pass) must not leave a tuft buried inside a trunk
    # or canopy block.
    seed = 42
    candidate = None
    for gx in range(-8, 9):
        for gz in range(-8, 9):
            candidate = vegetation.tree_candidate(gx, gz, seed)
            if candidate:
                break
        if candidate:
            break
    assert candidate is not None, "no tree candidate found"

    cells = vegetation.tree_blocks(
        candidate["origin_x"], candidate["origin_z"],
        candidate["surface"], candidate["height"], seed,
    )
    target = next(cell for cell in cells if cell[3] == BlockType.OAK_LEAVES)
    wx, wy, wz = target[:3]
    chunk_x, chunk_z = wx // 16, wz // 16
    local_x, local_z = wx - chunk_x * 16, wz - chunk_z * 16

    chunk = _fresh_chunk(chunk_x, chunk_z, seed)
    chunk.set_block(local_x, wy, local_z, BlockType.AIR)
    chunk.set_decoration(local_x, wy, local_z, 3)  # pre-existing tuft

    vegetation.generate_vegetation_for_chunk(chunk, seed)

    assert chunk.get_block(local_x, wy, local_z) == BlockType.OAK_LEAVES
    assert chunk.get_decoration(local_x, wy, local_z) == 0, "stale tuft left inside a tree"


def test_a_tuft_is_not_placed_on_a_surface_that_is_no_longer_grass():
    # Placement requires exposed grass, not merely "not a lake". Generated terrain
    # is always grass at the surface, so this rule only shows once an edit has
    # changed the support block and the chunk is generated again.
    seed = 42
    chunk_x, chunk_z = 3, 3
    chunk = _fresh_chunk(chunk_x, chunk_z, seed)
    vegetation.generate_vegetation_for_chunk(chunk, seed)

    found = None
    for x in range(chunk.SIZE_X):
        for z in range(chunk.SIZE_Z):
            gx, gz = chunk_x * 16 + x, chunk_z * 16 + z
            y = surface_height(seed, gx, gz) + 1
            if y <= 15 and chunk.get_decoration(x, y, z):
                found = (x, y, z)
                break
        if found:
            break
    assert found is not None, "sample chunk carries no tuft to test with"

    x, y, z = found
    chunk.set_block(x, y - 1, z, BlockType.STONE)  # support is no longer GRASS
    chunk.clear_decoration(x, y, z)
    chunk.set_block(x, y, z, BlockType.AIR)

    vegetation.generate_vegetation_for_chunk(chunk, seed)

    assert chunk.get_block(x, y, z) == BlockType.AIR
    assert chunk.get_decoration(x, y, z) == 0, "tuft placed on a non-grass surface"

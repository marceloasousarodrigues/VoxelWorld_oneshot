import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

import numpy

from block_data import BlockType
from terrain_generation import surface_height, in_lake, LAKE_RADIUS
from world import World
import vegetation


def test_surface_height_matches_generator():
    from terrain_generation import TerrainGenerator

    gen = TerrainGenerator()
    for (x, z) in [(0, 0), (5, -3), (-17, 22), (100, -100)]:
        assert surface_height(gen.seed, x, z) == gen._simple_terrain_height(x, z)


def test_hash32_is_stable_and_bounded():
    a = vegetation.hash32(42, 3, -7, 1)
    b = vegetation.hash32(42, 3, -7, 1)
    assert a == b
    assert 0 <= a < 2**32
    assert vegetation.hash32(42, 3, -7, 2) != vegetation.hash32(42, 3, -7, 1)


def test_in_lake_matches_radius():
    assert in_lake(0, 0) is True
    assert in_lake(LAKE_RADIUS + 5, 0) is False


REGION = [(cx, cz) for cx in range(-3, 2) for cz in range(-3, 2)]


def _fill_terrain(chunk, seed):
    for x in range(chunk.SIZE_X):
        for z in range(chunk.SIZE_Z):
            gx, gz = chunk.chunk_x * chunk.SIZE_X + x, chunk.chunk_z * chunk.SIZE_Z + z
            h = surface_height(seed, gx, gz)
            for y in range(h + 1):
                chunk.set_block(x, y, z, 1 if y == h else 2)  # GRASS / DIRT


def _region_world(seed, order):
    world = World()
    for (cx, cz) in order:
        chunk = world.get_chunk(cx, 0, cz)
        _fill_terrain(chunk, seed)
        vegetation.generate_vegetation_for_chunk(chunk, seed)
    return world


def _assert_regions_equal(a, b):
    assert set(a.chunks) == set(b.chunks)
    for key in a.chunks:
        assert numpy.array_equal(a.chunks[key].blocks, b.chunks[key].blocks), key
        assert numpy.array_equal(a.chunks[key].decorations, b.chunks[key].decorations), key


def test_region_permutations_produce_identical_blocks_and_decorations():
    orders = [
        REGION,
        list(reversed(REGION)),
        sorted(REGION, key=lambda k: (k[1], k[0])),
        sorted(REGION, key=lambda k: (-k[0], -k[1])),
    ]
    worlds = [_region_world(42, order) for order in orders]
    for other in worlds[1:]:
        _assert_regions_equal(worlds[0], other)

    # The comparison is only meaningful if the region actually grew trees and
    # tufts, so assert both are present rather than trusting an all-equal result.
    trees = sum(
        int(numpy.isin(chunk.blocks, [BlockType.OAK_LOG, BlockType.OAK_LEAVES]).sum())
        for chunk in worlds[0].chunks.values()
    )
    decorations = sum(int(chunk.decorations.sum()) for chunk in worlds[0].chunks.values())
    assert trees > 0
    assert decorations > 0


def test_identical_seed_is_reproducible_and_another_seed_differs():
    again = _region_world(42, REGION)
    _assert_regions_equal(again, _region_world(42, REGION))

    other = _region_world(43, REGION)
    differs = any(
        not numpy.array_equal(worlds_key.blocks, other.chunks[key].blocks)
        or not numpy.array_equal(worlds_key.decorations, other.chunks[key].decorations)
        for key, worlds_key in again.chunks.items()
    )
    assert differs, "seed 43 produced an identical world to seed 42"


def test_generate_vegetation_world_is_order_independent_and_repeatable():
    world = World()
    for (cx, cz) in REGION:
        _fill_terrain(world.get_chunk(cx, 0, cz), 42)
    before_blocks = sum(int(chunk.blocks.sum()) for chunk in world.chunks.values())
    assert sum(int(chunk.decorations.sum()) for chunk in world.chunks.values()) == 0

    vegetation.generate_vegetation(world, 42)

    after_blocks = sum(int(chunk.blocks.sum()) for chunk in world.chunks.values())
    after_decorations = sum(int(chunk.decorations.sum()) for chunk in world.chunks.values())
    assert after_blocks > before_blocks, "world generation added no trees"
    assert after_decorations > 0, "world generation added no tufts"

    first = {key: (chunk.blocks.copy(), chunk.decorations.copy())
             for key, chunk in world.chunks.items()}

    # Running it again must not change anything (idempotent).
    vegetation.generate_vegetation(world, 42)
    for key, chunk in world.chunks.items():
        assert numpy.array_equal(first[key][0], chunk.blocks), key
        assert numpy.array_equal(first[key][1], chunk.decorations), key

    # It must equal per-chunk generation performed in the opposite order.
    _assert_regions_equal(world, _region_world(42, list(reversed(REGION))))

"""M16 Task 2 — per-chunk generation must equal whole-world generation.

Streaming generates one chunk at a time, so ``TerrainGenerator.generate_chunk``
has to reproduce exactly what ``generate_world`` produces for that chunk. These
tests are the golden gate that protects the extraction from drifting.
"""

import hashlib
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from block_data import BlockType  # noqa: E402
from terrain_generation import TerrainGenerator, surface_height  # noqa: E402
from world import World  # noqa: E402

INITIAL_CHUNKS = [(cx, cz) for cx in (-1, 0, 1) for cz in (-1, 0, 1)]


def _fingerprint(chunk):
    return (
        hashlib.sha256(chunk.blocks.tobytes()).hexdigest(),
        hashlib.sha256(chunk.decorations.tobytes()).hexdigest(),
        hashlib.sha256(chunk.water_levels.tobytes()).hexdigest(),
        hashlib.sha256(chunk.water_sources.tobytes()).hexdigest(),
    )


def test_per_chunk_generation_matches_generate_world():
    whole = World()
    TerrainGenerator().generate_world(whole)

    per_chunk = World()
    generator = TerrainGenerator()
    for chunk_x, chunk_z in INITIAL_CHUNKS:
        generator.generate_chunk(per_chunk, chunk_x, 0, chunk_z)

    assert set(whole.chunks) == set(per_chunk.chunks)
    for key in whole.chunks:
        assert _fingerprint(whole.chunks[key]) == _fingerprint(per_chunk.chunks[key]), key


def test_generate_chunk_returns_the_registered_chunk():
    world = World()
    generator = TerrainGenerator()
    chunk = generator.generate_chunk(world, 3, 0, 4)

    assert world.chunks[(3, 0, 4)] is chunk
    assert chunk.chunk_x == 3 and chunk.chunk_z == 4


def test_generate_chunk_outside_the_initial_region_is_correct():
    world = World()
    generator = TerrainGenerator()
    chunk_x, chunk_z = 5, -3
    chunk = generator.generate_chunk(world, chunk_x, 0, chunk_z)

    base_x = chunk_x * 16
    base_z = chunk_z * 16
    # These columns are far from the deterministic lake, so the documented pure
    # rule applies: grass at the surface, air above, dirt for three cells below,
    # stone underneath.
    for local_x in (0, 7, 15):
        for local_z in (0, 7, 15):
            surface = surface_height(generator.seed, base_x + local_x, base_z + local_z)
            # Trees may occupy cells above the surface, but generation never
            # writes at or below it, so the terrain rule holds there exactly.
            for y in range(surface + 1):
                if y == surface:
                    expected = BlockType.GRASS
                elif y > surface - 4:
                    expected = BlockType.DIRT
                else:
                    expected = BlockType.STONE
                assert int(chunk.blocks[local_x, y, local_z]) == expected, (
                    local_x,
                    y,
                    local_z,
                )


def test_generate_chunk_for_non_ground_layer_is_empty():
    world = World()
    generator = TerrainGenerator()
    chunk = generator.generate_chunk(world, 0, 1, 0)

    assert int(chunk.blocks.max()) == BlockType.AIR
    assert int(chunk.decorations.max()) == 0

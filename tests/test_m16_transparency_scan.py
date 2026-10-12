"""M16 stutter fix 2 - vectorised chunk transparency scan.

``chunk_entity.create_chunk_entity`` used to decide whether a chunk contains any
transparent block with a Python triple loop over all 4096 cells, reading numpy
scalars one at a time (measured 4.33 ms per chunk, 4096 ``is_block_transparent``
calls per load). The vectorised predicate is equivalent by construction and
measured 0.028 ms per chunk.

These tests pin the equivalence, not the speed: the old loop is kept here as the
oracle, and the predicate must agree with it on real generated chunks.
"""

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from block_data import (  # noqa: E402
    BLOCK_PROPERTIES,
    BlockType,
    is_block_transparent,
    has_transparent_block,
)
from chunk import Chunk  # noqa: E402
from terrain_generation import TerrainGenerator  # noqa: E402
from world import World  # noqa: E402

TRANSPARENT_IDS = [
    int(block_type)
    for block_type, props in BLOCK_PROPERTIES.items()
    if props.get("is_transparent", False)
]


def legacy_scan(blocks) -> bool:
    """The pre-fix triple loop, kept verbatim as the oracle."""
    has_any_transparent_block = False
    for x in range(Chunk.SIZE_X):
        for y in range(Chunk.SIZE_Y):
            for z in range(Chunk.SIZE_Z):
                if is_block_transparent(blocks[x, y, z]):
                    has_any_transparent_block = True
                    break
            if has_any_transparent_block:
                break
        if has_any_transparent_block:
            break
    return has_any_transparent_block


def test_predicate_is_true_for_a_chunk_containing_water():
    chunk = Chunk(0, 0, 0)
    chunk.set_block(3, 4, 5, BlockType.WATER)
    assert has_transparent_block(chunk.blocks) is True
    assert chunk.has_transparent_block() is True


def test_predicate_is_false_for_an_all_air_chunk():
    chunk = Chunk(0, 0, 0)
    assert has_transparent_block(chunk.blocks) is False
    assert chunk.has_transparent_block() is False


def test_predicate_is_false_for_only_opaque_solid_blocks():
    chunk = Chunk(0, 0, 0)
    for x in range(Chunk.SIZE_X):
        for y in range(Chunk.SIZE_Y):
            for z in range(Chunk.SIZE_Z):
                chunk.set_block(x, y, z, BlockType.STONE)
    assert has_transparent_block(chunk.blocks) is False


def test_predicate_is_false_for_leaves_and_logs():
    """M14 foliage is opaque-pass geometry, not the transparent pass."""
    chunk = Chunk(0, 0, 0)
    chunk.set_block(1, 1, 1, BlockType.OAK_LEAVES)
    chunk.set_block(2, 2, 2, BlockType.OAK_LOG)
    assert has_transparent_block(chunk.blocks) is False


def test_predicate_agrees_with_the_legacy_scan_on_generated_chunks():
    """The equivalence gate: real generated chunks, including the lake."""
    world = World()
    TerrainGenerator().generate_world(world)
    assert world.chunks, "generator must produce chunks"

    comparisons = 0
    for chunk in world.chunks.values():
        assert has_transparent_block(chunk.blocks) == legacy_scan(chunk.blocks), (
            f"disagreement at chunk {(chunk.chunk_x, chunk.chunk_y, chunk.chunk_z)}"
        )
        comparisons += 1
    assert comparisons >= 9


def test_predicate_agrees_with_the_legacy_scan_on_a_streamed_chunk():
    """A chunk generated through the streaming entry point, not the whole world."""
    world = World()
    generator = TerrainGenerator()
    chunk = generator.generate_chunk(world, 4, 0, 4)
    assert has_transparent_block(chunk.blocks) == legacy_scan(chunk.blocks)


def test_predicate_handles_negative_and_extreme_block_values_safely():
    """An unknown block value is simply not transparent.

    The legacy per-cell scan raised ``KeyError`` on such a value, because
    ``is_block_transparent`` indexes the property table directly; the vectorised
    comparison cannot. This is a strict widening, not a behaviour change for any
    real block type.
    """
    chunk = Chunk(0, 0, 0)
    chunk.blocks[0, 0, 0] = -1
    assert has_transparent_block(chunk.blocks) is False
    try:
        legacy_scan(chunk.blocks)
    except KeyError:
        pass
    else:  # pragma: no cover - documents the old behaviour if it ever changes
        raise AssertionError("the legacy scan was expected to reject unknown ids")


def test_only_water_is_a_transparent_block_in_this_world():
    """If a block type ever becomes transparent, this test is the tripwire."""
    assert TRANSPARENT_IDS == [int(BlockType.WATER)]


if __name__ == "__main__":
    test_predicate_is_true_for_a_chunk_containing_water()
    test_predicate_is_false_for_an_all_air_chunk()
    test_predicate_is_false_for_only_opaque_solid_blocks()
    test_predicate_is_false_for_leaves_and_logs()
    test_predicate_agrees_with_the_legacy_scan_on_generated_chunks()
    test_predicate_agrees_with_the_legacy_scan_on_a_streamed_chunk()
    test_predicate_handles_negative_and_extreme_block_values_safely()
    test_transparent_ids_match_the_property_table()
    print("M16 transparency scan tests passed!")

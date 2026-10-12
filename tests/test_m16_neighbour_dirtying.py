"""M16 Task 3 — neighbour re-culling on load/unload.

The mesher treats an unloaded neighbour as AIR, so a chunk's boundary faces
change when a neighbour loads or unloads. Every load/unload must therefore mark
the chunk's *loaded* neighbours dirty; nothing else.
"""

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from terrain_generation import TerrainGenerator  # noqa: E402
from world import World  # noqa: E402


def test_loading_a_neighbour_marks_the_existing_chunk_dirty():
    world = World()
    generator = TerrainGenerator()
    world.load_chunk(0, 0, 0, terrain_generator=generator)
    world.refresh()
    assert world.dirty_chunks == set()

    world.load_chunk(1, 0, 0, terrain_generator=generator)

    # Chunk (0,0,0) must re-cull its +X boundary face against the new neighbour.
    assert (0, 0, 0) in world.dirty_chunks


def test_unloading_a_neighbour_marks_the_remaining_chunk_dirty():
    world = World()
    generator = TerrainGenerator()
    world.load_chunk(0, 0, 0, terrain_generator=generator)
    world.load_chunk(0, 0, 1, terrain_generator=generator)
    world.refresh()
    assert world.dirty_chunks == set()

    world.unload_chunk(0, 0, 1)

    # Chunk (0,0,0) must re-expose its +Z boundary face.
    assert (0, 0, 0) in world.dirty_chunks


def test_loading_an_isolated_chunk_dirties_nothing_else():
    world = World()
    generator = TerrainGenerator()
    world.load_chunk(5, 0, 5, terrain_generator=generator)

    assert world.dirty_chunks <= {(5, 0, 5)}
    assert (5, 0, 5) not in world.dirty_chunks

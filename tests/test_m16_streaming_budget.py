"""M16 Task 4 — per-frame streaming budget and convergence.

Streaming must make bounded, incremental progress each update, load the nearest
chunks first, unload chunks beyond the retention radius, and eventually converge
to exactly the desired set with one entity per loaded chunk.
"""

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from chunk_streaming import ChunkStreamer  # noqa: E402
from terrain_generation import TerrainGenerator  # noqa: E402
from world import World  # noqa: E402


def _streamer(world, **overrides):
    defaults = dict(
        streaming_distance=1,
        retention_distance=1,
        max_loads_per_frame=1,
        max_unloads_per_frame=1,
        terrain_generator=TerrainGenerator(),
    )
    defaults.update(overrides)
    return ChunkStreamer(world, **defaults)


def test_update_loads_at_most_the_budget_per_frame():
    world = World()
    streamer = _streamer(world, max_loads_per_frame=1)

    result = streamer.update((8, 8, 8))

    assert result["loaded"] == 1
    assert len(world.chunks) == 1


def test_first_load_is_the_players_own_chunk():
    world = World()
    streamer = _streamer(world, max_loads_per_frame=1)

    streamer.update((8, 8, 8))

    assert (0, 0, 0) in world.chunks


def test_update_unloads_at_most_the_budget_per_frame():
    world = World()
    generator = TerrainGenerator()
    for chunk_x in range(-2, 3):
        for chunk_z in range(-2, 3):
            world.load_chunk(chunk_x, 0, chunk_z, terrain_generator=generator)
    assert len(world.chunks) == 25

    streamer = _streamer(
        world,
        max_loads_per_frame=1,
        max_unloads_per_frame=2,
        retention_distance=0,
        streaming_distance=0,
    )
    result = streamer.update((8, 8, 8))  # stay in chunk (0,0)

    assert result["unloaded"] == 2
    assert len(world.chunks) == 23


def test_convergence_reaches_exactly_the_desired_set():
    world = World()
    streamer = _streamer(world, streaming_distance=1, retention_distance=1)

    position = (40, 8, -40)
    desired = streamer.desired_chunk_keys(position)

    for _ in range(500):
        streamer.update(position)
        if not streamer.has_pending_work():
            break
    else:
        raise AssertionError("streaming did not converge")

    assert set(world.chunks) == desired
    assert len(streamer.rendered) == len(world.chunks)


def test_same_chunk_is_a_no_op_once_converged():
    world = World()
    streamer = _streamer(world, streaming_distance=1, retention_distance=1)
    position = (8, 8, 8)

    for _ in range(500):
        streamer.update(position)
        if not streamer.has_pending_work():
            break

    result = streamer.update(position)

    assert result["loaded"] == 0
    assert result["unloaded"] == 0


def test_moving_across_a_boundary_leaves_no_duplicates():
    world = World()
    streamer = _streamer(
        world,
        streaming_distance=1,
        retention_distance=1,
        max_loads_per_frame=16,
        max_unloads_per_frame=16,
    )

    for position in ((8, 8, 8), (24, 8, 8), (8, 8, 8), (-8, 8, 8), (8, 8, 8)):
        for _ in range(50):
            streamer.update(position)
            if not streamer.has_pending_work():
                break

        # One registry entry and one rendered entity per loaded chunk, exactly.
        assert set(streamer.rendered) == set(world.chunks)
        assert len(world.chunks) <= 9

    # Every rendered entity belongs to a registered chunk, and vice versa.
    for key, entity in streamer.rendered.items():
        assert world.chunks[key].entity is entity

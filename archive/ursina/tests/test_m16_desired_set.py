"""M16 Task 4 — streaming distance and the desired/retained chunk sets.

The desired set is a Chebyshev (square) radius, in chunks, around the player's
chunk on the ground layer only. Retention is the larger radius outside which
chunks unload, and must always contain the desired set.
"""

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from chunk_streaming import ChunkStreamer  # noqa: E402
from world import World  # noqa: E402


def _streamer(**overrides):
    world = World()
    defaults = dict(
        streaming_distance=1,
        retention_distance=1,
        max_loads_per_frame=1,
        max_unloads_per_frame=1,
    )
    defaults.update(overrides)
    return ChunkStreamer(world, **defaults)


def test_desired_set_is_a_chebyshev_radius_at_origin():
    streamer = _streamer()
    desired = streamer.desired_chunk_keys((8, 8, 8))

    expected = {(dx, 0, dz) for dx in (-1, 0, 1) for dz in (-1, 0, 1)}
    assert desired == expected


def test_desired_set_uses_floor_for_negative_chunk_coordinates():
    streamer = _streamer()
    desired = streamer.desired_chunk_keys((-24, 8, -24))

    # -24 // 16 == -2, so the player's chunk is (-2, 0, -2).
    expected = {(-2 + dx, 0, -2 + dz) for dx in (-1, 0, 1) for dz in (-1, 0, 1)}
    assert desired == expected


def test_retained_set_contains_the_desired_set():
    streamer = _streamer(streaming_distance=2, retention_distance=4)
    position = (37, 8, -51)

    assert streamer.retained_chunk_keys(position) > streamer.desired_chunk_keys(position)


def test_retention_is_clamped_up_to_streaming():
    streamer = _streamer(streaming_distance=3, retention_distance=1)

    assert streamer.retention_distance >= streamer.streaming_distance

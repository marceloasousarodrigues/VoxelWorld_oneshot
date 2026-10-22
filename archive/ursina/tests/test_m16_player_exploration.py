"""M16 — the real player can explore past the initial generated region.

Streaming must keep chunks loaded ahead of the player so the M6 generated-world
boundary guard no longer pins the player to the original 3x3 region. This drives
the actual player movement + collision code, not a teleport.
"""

import sys
from math import floor
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from chunk_streaming import ChunkStreamer  # noqa: E402
from player import VoxelPlayer  # noqa: E402
from terrain_generation import TerrainGenerator  # noqa: E402
from world import World  # noqa: E402

INITIAL_MAX = 2 * 16 - 1  # the initial 3x3 region reaches chunk coordinate 1


def test_player_walks_past_the_initial_region_with_streaming():
    world = World()
    generator = TerrainGenerator()
    generator.generate_world(world)

    streamer = ChunkStreamer(
        world,
        terrain_generator=generator,
        streaming_distance=2,
        retention_distance=3,
        max_loads_per_frame=2,
        max_unloads_per_frame=2,
    )

    player = VoxelPlayer(world, spawn_position=(8, 8, 8))
    player.rotation_y = 0  # forward along +Z
    player.keys["w"] = True

    for _ in range(2400):
        player._update_horizontal_movement(1 / 60)
        player._update_vertical_movement(1 / 60)
        streamer.update((player.x, player.y, player.z))
        world.reconcile()

    # The player must have left the original region rather than being walled in.
    assert floor(player.z) > INITIAL_MAX, f"player did not explore: z={player.z}"
    assert player.y > 0, "player fell out of the world"
    assert player.on_ground, "player is not standing on terrain"

    # Streaming loaded chunks beyond the original region; every rendered key is a
    # registered chunk, and the registry holds exactly one entity per chunk.
    assert any(key[2] > 1 for key in world.chunks)
    assert set(streamer.rendered) == set(world.chunks)
    for key, entity in streamer.rendered.items():
        assert world.chunks[key].entity is entity

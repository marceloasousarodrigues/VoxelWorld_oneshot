"""Regression tests for the generated-world boundary.

Reads used to create chunks as a side effect, which made the player's
"is this chunk generated" guard self-fulfilling: the guard, the camera ray and
the ground scan all generated the very chunks they were asking about, so the
player could walk out of the generated region and fall forever.
"""
import sys
from math import floor
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from block_data import BlockType
from player import VoxelPlayer
from terrain_generation import TerrainGenerator
from world import World

CHUNK_SIZE = 16


def test_reading_a_block_does_not_create_a_chunk():
    world = World()

    assert world.get_block(999, 5, 999) == BlockType.AIR

    assert (999 // CHUNK_SIZE, 0, 999 // CHUNK_SIZE) not in world.chunks
    assert world.chunks == {}


def test_reads_still_see_written_blocks():
    world = World()
    world.set_block(5, 3, 7, BlockType.STONE)

    assert world.get_block(5, 3, 7) == BlockType.STONE
    assert world.get_block(5, 4, 7) == BlockType.AIR


def test_chunk_exists_does_not_generate_the_chunk_it_asks_about():
    world = World()
    world.get_chunk(0, 0, 0)
    player = VoxelPlayer(world, spawn_position=(8, 10, 8))

    assert player._chunk_exists(0, 0) is True
    assert player._chunk_exists(7, 7) is False

    # Asking must not have generated the chunk.
    assert (7, 0, 7) not in world.chunks
    assert len(world.chunks) == 1


def test_player_stays_inside_the_generated_world_and_never_falls_out():
    world = World()
    TerrainGenerator().generate_world(world)
    generated_at_start = set(world.chunks)

    # The generated region is 3x3 chunks, i.e. x, z in [-16, 31]; the spawn is
    # inside it, so walking far enough in any direction reaches an edge.
    for heading in range(0, 360, 45):
        player = VoxelPlayer(world, spawn_position=(8, 8, 8))
        player.rotation_y = heading
        player.keys["w"] = True

        # Walk straight at that edge for 15 simulated seconds while raycasting
        # every frame, exactly like the running game does.
        for _ in range(900):
            player._update_horizontal_movement(1 / 60)
            player._update_vertical_movement(1 / 60)
            player._update_interaction()

        assert player.y > 0, f"heading {heading}: fell out of the world to y={player.y}"
        assert player.find_ground_y() is not None, f"heading {heading}: no ground below"
        assert player.on_ground, f"heading {heading}: not standing on ground"
        assert floor(player.x) >= -CHUNK_SIZE, f"heading {heading}: left at x={player.x}"
        assert floor(player.x) <= 2 * CHUNK_SIZE - 1
        assert floor(player.z) >= -CHUNK_SIZE, f"heading {heading}: left at z={player.z}"
        assert floor(player.z) <= 2 * CHUNK_SIZE - 1

    assert set(world.chunks) == generated_at_start, "phantom chunks were created"

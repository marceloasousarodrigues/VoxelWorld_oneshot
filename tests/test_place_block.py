import sys
sys.path.append('.')

from player import VoxelPlayer
from world import World
from block_data import BlockType

DIRT = BlockType.DIRT
STONE = BlockType.STONE
AIR = BlockType.AIR


def make_player(blocks=(), origin=(0.5, 0.5, 0.5), direction=(1, 0, 0),
                interaction_range=6.0, player_pos=(8, 10, 8)):
    world = World()
    for (x, y, z), b in blocks:
        world.set_block(x, y, z, b)
    world.refresh()
    player = VoxelPlayer(world, spawn_position=player_pos)
    player.interaction_range = interaction_range
    # Add items for placement tests
    player.inventory.add_item(DIRT, 64) 
    player.inventory.add_item(STONE, 64)
    # stub ray to deterministic origin/direction
    player.get_interaction_ray = lambda: (origin, direction)
    return player, world


def test_place_block_success_on_air_neighbor():
    # DIRT at +x neighbor should be filled
    # Existing block at (2,0,0), ray hits it from the -x face -> neighbor (1,0,0) is AIR -> success
    player, world = make_player([((2, 0, 0), DIRT)], origin=(0.5, 0.5, 0.5), direction=(1, 0, 0))
    # Player is far away so no overlap
    target = player.place_block()
    assert target == (1, 0, 0)
    assert world.get_block(1, 0, 0) == DIRT


def test_place_block_rejects_occupied_target():
    # Blocks at 0 and 1, so the neighbor (0,0,0) is occupied -> reject
    player, world = make_player([((0, 0, 0), DIRT), ((1, 0, 0), DIRT)], origin=(0.5, 0.5, 0.5), direction=(1, 0, 0))
    before = world.get_block(0, 0, 0)
    assert player.place_block() is None
    assert world.get_block(0, 0, 0) == before


def test_place_block_rejects_inside_player_body():
    # Player at (8, 1, 8) eye ~2.6. Aim so neighbor would be player's voxel.
    # Simpler: put a block in front, neighbor overlaps player position.
    player, world = make_player([((9, 1, 8), DIRT)], origin=(8.5, 1.6, 8), direction=(1, 0, 0), player_pos=(8, 1, 8))
    # Ray hits (9,1,8), neighbor is (8,1,8) which is the player's ground column
    assert player.place_block() is None
    assert world.get_block(8, 1, 8) == AIR


def test_place_block_valid_outside_player_does_not_overlap():
    # Player at origin, place on far side of a hit block
    player, world = make_player([((2, 0, 0), DIRT)], origin=(0.5, 0.5, 0.5), direction=(1, 0, 0), player_pos=(8, 10, 8))
    target = player.place_block()
    assert target is not None
    assert world.get_block(*target) == DIRT


def test_place_block_at_chunk_boundary_refreshes_neighbors():
    # Block at chunk boundary x=15, neighbor 16 is across chunks
    world = World()
    world.set_block(15, 0, 0, STONE)
    world.refresh()
    player = VoxelPlayer(world, spawn_position=(8, 10, 8))
    player.inventory.add_item(DIRT, 64) # Add DIRT for placement
    player.interaction_range = 6.0
    # Approach from +x side so neighbor is (16,0,0) across chunk boundary
    player.get_interaction_ray = lambda: ((17.5, 0.5, 0.5), (-1, 0, 0))
    target = player.place_block()
    assert target == (16, 0, 0)
    assert world.get_block(16, 0, 0) == DIRT
    # Original block untouched, dirty set cleared by refresh
    assert world.get_block(15, 0, 0) == STONE
    assert not world.dirty_chunks


def test_right_mouse_down_triggers_place():
    player, world = make_player([((2, 0, 0), DIRT)], origin=(0.5, 0.5, 0.5), direction=(1, 0, 0))
    player.input('right mouse down')
    assert world.get_block(1, 0, 0) == DIRT


def test_right_mouse_up_and_left_do_not_trigger_place():
    player, world = make_player([((2, 0, 0), DIRT)], origin=(0.5, 0.5, 0.5), direction=(1, 0, 0))
    player.input('left mouse down')
    assert world.get_block(1, 0, 0) == AIR  # break consumes the hit, no placement side-effect
    # reset
    player, world = make_player([((2, 0, 0), DIRT)], origin=(0.5, 0.5, 0.5), direction=(1, 0, 0))
    player.input('right mouse up')
    assert world.get_block(1, 0, 0) == AIR
    player.input('right mouse down hold')
    assert world.get_block(1, 0, 0) == AIR


def test_missing_hit_or_no_world_is_safe():
    player, world = make_player([], origin=(0.5, 0.5, 0.5), direction=(1, 0, 0))
    assert player.place_block() is None
    player.world = None
    assert player.place_block() is None


if __name__ == "__main__":
    test_place_block_success_on_air_neighbor()
    test_place_block_rejects_occupied_target()
    test_place_block_rejects_inside_player_body()
    test_place_block_valid_outside_player_does_not_overlap()
    test_place_block_at_chunk_boundary_refreshes_neighbors()
    test_right_mouse_down_triggers_place()
    test_right_mouse_up_and_left_do_not_trigger_place()
    test_missing_hit_or_no_world_is_safe()
    print("All placement tests passed!")

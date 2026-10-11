import sys
sys.path.append('.')

from player import VoxelPlayer
from world import World
from block_data import BlockType

# Test constants
DIRT = BlockType.DIRT
STONE = BlockType.STONE
AIR = BlockType.AIR


def make_player(blocks=(), origin=(0.5, 0.5, 0.5), direction=(1, 0, 0),
                interaction_range=6.0):
    """
    Build a VoxelPlayer over a World with the given blocks.

    The interaction ray is stubbed to a fixed origin/direction so the
    break logic is tested independently of the Ursina camera transform.
    """
    world = World()
    for (x, y, z), block_type in blocks:
        world.set_block(x, y, z, block_type)

    player = VoxelPlayer(world)
    player.interaction_range = interaction_range
    player.get_interaction_ray = lambda: (origin, direction)
    return player, world


def test_break_block_removes_hit_block():
    player, world = make_player([((2, 0, 0), DIRT)])

    broken = player.break_block()

    assert broken == (2, 0, 0)
    assert world.get_block(2, 0, 0) == AIR


def test_break_block_only_breaks_first_solid_block():
    # A dirt block in front of a stone block: only the dirt may change.
    player, world = make_player([((2, 0, 0), DIRT), ((4, 0, 0), STONE)])

    broken = player.break_block()

    assert broken == (2, 0, 0)
    assert world.get_block(2, 0, 0) == AIR
    # The block behind the hit and empty cells must be untouched.
    assert world.get_block(4, 0, 0) == STONE
    assert world.get_block(1, 0, 0) == AIR
    assert world.get_block(3, 0, 0) == AIR


def test_break_block_does_nothing_on_empty_space():
    player, world = make_player([])

    assert player.break_block() is None


def test_break_block_ignores_blocks_beyond_range():
    # Distance from x=0.5 to the x=7 cell is 6.5, beyond the 6-block range.
    player, world = make_player([((7, 0, 0), DIRT)], interaction_range=6.0)

    assert player.break_block() is None
    assert world.get_block(7, 0, 0) == DIRT


def test_break_block_breaks_block_at_range_edge():
    # Distance from x=0.5 to the x=6 cell is 5.5, within the 6-block range.
    player, world = make_player([((6, 0, 0), DIRT)], interaction_range=6.0)

    assert player.break_block() == (6, 0, 0)
    assert world.get_block(6, 0, 0) == AIR


def test_break_block_uses_configured_interaction_range():
    # With a 2-block range, a block 2.5 away must not be broken...
    player, world = make_player([((3, 0, 0), STONE)], interaction_range=2.0)
    assert player.break_block() is None
    assert world.get_block(3, 0, 0) == STONE

    # ...but a block within 2 blocks is broken.
    player, world = make_player([((1, 0, 0), DIRT)], interaction_range=2.0)
    assert player.break_block() == (1, 0, 0)
    assert world.get_block(1, 0, 0) == AIR


def test_break_block_returns_none_without_world():
    player, _ = make_player([])
    player.world = None

    assert player.break_block() is None


def test_left_mouse_down_triggers_break():
    player, world = make_player([((2, 0, 0), DIRT)])

    player.input('left mouse down')

    assert world.get_block(2, 0, 0) == AIR


def test_left_mouse_up_does_not_break():
    # Releasing the button must not break anything (no continuous breaking).
    player, world = make_player([((2, 0, 0), DIRT)])

    player.input('left mouse up')

    assert world.get_block(2, 0, 0) == DIRT


def test_unrelated_keys_do_not_break():
    player, world = make_player([((2, 0, 0), DIRT)])

    for key in ('w', 'a', 's', 'd', 'space', 'right mouse down', 'left mouse down hold'):
        player.input(key)

    assert world.get_block(2, 0, 0) == DIRT


def test_interaction_ray_uses_camera_forward():
    from ursina import camera

    # Note: no ray stub here - exercise the real get_interaction_ray.
    world = World()
    player = VoxelPlayer(world)

    origin, direction = player.get_interaction_ray()

    assert tuple(origin) == tuple(player.position + (0, player.eye_height, 0))
    assert tuple(direction) == tuple(camera.forward)


def test_interaction_ray_follows_camera_pitch():
    from ursina import camera

    world = World()
    player = VoxelPlayer(world)
    player.rotation = (0, 0, 0)

    previous_rotation = camera.rotation
    try:
        # Look down: the camera forward must gain a vertical component.
        camera.rotation = (45, 0, 0)
        origin, direction = player.get_interaction_ray()

        assert abs(direction[1]) > 0.1
        # Therefore the ray must differ from the player's horizontal forward.
        assert tuple(direction) != tuple(player.forward)
    finally:
        camera.rotation = previous_rotation


if __name__ == "__main__":
    test_break_block_removes_hit_block()
    test_break_block_only_breaks_first_solid_block()
    test_break_block_does_nothing_on_empty_space()
    test_break_block_ignores_blocks_beyond_range()
    test_break_block_breaks_block_at_range_edge()
    test_break_block_uses_configured_interaction_range()
    test_break_block_returns_none_without_world()
    test_left_mouse_down_triggers_break()
    test_left_mouse_up_does_not_break()
    test_unrelated_keys_do_not_break()
    test_interaction_ray_uses_camera_forward()
    test_interaction_ray_follows_camera_pitch()
    print("All break-block tests passed!")

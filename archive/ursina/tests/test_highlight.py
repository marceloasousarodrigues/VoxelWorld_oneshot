import sys
sys.path.append('.')
from player import VoxelPlayer
from world import World
from block_data import BlockType
from ursina import Entity

# Setup
def make_player(blocks=(), origin=(0.5, 0.5, 0.5), direction=(1, 0, 0)):
    world = World()
    for (x,y,z), b in blocks: world.set_block(x,y,z,b)
    player = VoxelPlayer(world)
    player.get_interaction_ray = lambda: (origin, direction)
    return player, world

def test_highlight_appears_on_hit():
    player, world = make_player([((2, 0, 0), BlockType.DIRT)])
    player._update_interaction()
    assert player.highlight.highlight_entity is not None
    # Position should be centered in the voxel (2+0.5, 0+0.5, 0+0.5)
    assert player.highlight.highlight_entity.position == (2.5, 0.5, 0.5)
    assert player.highlight.highlight_entity.visible == True

def test_highlight_disappears_on_miss():
    player, world = make_player([])
    player._update_interaction()
    assert player.highlight.highlight_entity is None

# def test_crosshair_exists():
#     from ursina import camera, Vec3, color
#     found = False
#     for e in camera.ui.children:
#         # Crosshair has scale 0.01, model quad, color white
#         if e.model and e.model.name == 'quad' and e.scale[0] == 0.01 and e.color == color.white:
#             found = True
#             break
#     assert found


if __name__ == "__main__":
    test_highlight_appears_on_hit()
    test_highlight_disappears_on_miss()
    print("All highlight tests passed!")

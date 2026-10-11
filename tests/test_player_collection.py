import sys
sys.path.append('.')

from player import VoxelPlayer
from world import World
from block_data import BlockType

# Test constants
DIRT = BlockType.DIRT
AIR = BlockType.AIR

def make_player(blocks=(), origin=(0.5, 0.5, 0.5), direction=(1, 0, 0)):
    world = World()
    for (x, y, z), b in blocks:
        world.set_block(x, y, z, b)
    world.refresh()
    player = VoxelPlayer(world)
    player.get_interaction_ray = lambda: (origin, direction)
    return player, world

def test_break_block_collects_item():
    player, world = make_player([((2, 0, 0), DIRT)])
    
    player.break_block()
    
    assert world.get_block(2, 0, 0) == AIR
    assert player.inventory.get_qty(DIRT) == 1

def test_break_block_fails_when_inventory_full():
    # Size 1 (1 slot max)
    player, world = make_player([((2, 0, 0), DIRT)])
    player.inventory.size = 1
    # Fill slot
    player.inventory.add_item(DIRT, 64)
    
    # Try breaking - should fail
    result = player.break_block()
    
    # Should NOT be empty
    assert result is None
    assert world.get_block(2, 0, 0) == DIRT
    # Quantity unchanged
    assert player.inventory.get_qty(DIRT) == 64

if __name__ == "__main__":
    test_break_block_collects_item()
    test_break_block_fails_when_inventory_full()
    print("All collection tests passed!")

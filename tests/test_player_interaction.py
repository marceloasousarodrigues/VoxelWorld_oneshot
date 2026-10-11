import sys
sys.path.append('.')

from player import VoxelPlayer  
from world import World
from block_data import BlockType

def test_player_interaction():
    world = World()
    
    # Place a block at (0, 0, 0)
    world.set_block(0, 0, 0, BlockType.DIRT) 
    
    # Create a player with the world
    player = VoxelPlayer(world)
    
    # Test that player's interaction state is initialized
    assert hasattr(player, 'interaction_state')
    
    print("Player interaction test passed!")

if __name__ == "__main__":
    test_player_interaction()
    print("All tests passed!")
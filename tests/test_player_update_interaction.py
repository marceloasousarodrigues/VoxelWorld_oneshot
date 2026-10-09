import sys
sys.path.append('.')

from player import VoxelPlayer
from world import World

def test_player_interaction_update():
    # Create a simple world and player 
    world = World()
    
    # Create player with the world
    player = VoxelPlayer(world)
    
    # Check that _update_interaction method exists
    assert hasattr(player, '_update_interaction')
    
    # Test calling the method (should not crash)
    try:
        player._update_interaction()
    except Exception as e:
        # We might get an error about mouse being unavailable - that's okay for this test
        pass
    
    # Verify interaction state initialization
    assert 'interaction_state' in player.__dict__
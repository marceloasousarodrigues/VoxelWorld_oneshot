import sys
sys.path.append('.')

from player import VoxelPlayer
from world import World

def test_player_interaction_state():
    # Create a simple world and player 
    world = World()
    
    # Create player with the world
    player = VoxelPlayer(world)
    
    # Check that interaction state exists
    assert 'interaction_state' in player.__dict__
    
    # Check interaction state attributes
    state = player.interaction_state
    assert 'left_button' in state
    assert 'right_button' in state
    assert 'last_interaction_point' in state
    assert 'highlighted_block' in state
    
    # Check default values
    assert state['left_button'] is False
    assert state['right_button'] is False
    assert state['last_interaction_point'] is None
    assert state['highlighted_block'] is None
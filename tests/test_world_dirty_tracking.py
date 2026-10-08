import sys
sys.path.append('.')

from world import World

def test_world_dirty_tracking():
    world = World()
    chunk_id = (0, 0)
    assert chunk_id not in world.dirty_chunks
    
    # Mark chunk as dirty
    world.dirty(chunk_id)
    assert chunk_id in world.dirty_chunks
    
    # Refresh should clear the dirty set
    world.refresh()  
    assert chunk_id not in world.dirty_chunks
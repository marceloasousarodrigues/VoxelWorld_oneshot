import sys
sys.path.append('.')

from world import World
from block_data import BlockType

DIRT = BlockType.DIRT

def test_set_block_marks_dirty():
    world = World()
    pos = (0, 0, 0)
    
    # Before setting block, ensure no dirty chunks
    assert not world.dirty_chunks
    
    # Set a block and check if chunk gets marked dirty
    world.set_block(pos[0], pos[1], pos[2], DIRT)
    
    expected_chunk_id = (0, 0, 0)
    assert expected_chunk_id in world.dirty_chunks
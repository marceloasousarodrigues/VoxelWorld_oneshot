import sys
sys.path.append('.')

from world import World
from block_data import BlockType

# Test constants
DIRT = BlockType.DIRT
AIR = 0

def test_set_block_marks_dirty():
    world = World()
    
    # Before setting block, ensure no dirty chunks
    assert not world.dirty_chunks
    
    # Set a block and check if chunk gets marked dirty
    world.set_block(0, 0, 0, DIRT)
    
    expected_chunk_id = (0, 0, 0)
    assert expected_chunk_id in world.dirty_chunks

if __name__ == "__main__":
    test_set_block_marks_dirty()
    print("World set_block test passed!")
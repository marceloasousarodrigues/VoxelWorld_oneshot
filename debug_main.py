"""
Debug version of main to test visualization.
"""
import sys
from ursina import *
from ursina.prefabs.first_person_controller import FirstPersonController
from chunk import Chunk
from block_data import BlockType
from chunk_entity import create_chunk_entity

app = Ursina()

# Create a simple test case first
def test_chunk_visualization():
    print("Creating test chunk...")
    
    # Create a chunk with blocks
    test_chunk = Chunk(0, 0, 0)
    test_chunk.set_block(0, 0, 0, BlockType.GRASS)
    test_chunk.set_block(1, 0, 0, BlockType.STONE)
    
    print("About to create entity...")
    # Create chunk entity
    entity = create_chunk_entity(test_chunk, (0, 0, 0))
    
    if entity:
        print(f"SUCCESS: Created entity with mesh")
        print(f"Entity has mesh: {entity.mesh is not None}")
        print(f"Entity has position: {entity.position}")
    else:
        print("FAILED: Could not create entity")
        
    return entity

# Create player
player = FirstPersonController(
    position=(0, 10, 0),
    collider='box'
)

# Create and test our chunk
chunk_entity = test_chunk_visualization()

def update():
    pass

def input(key):
    if key == 'q':
        sys.exit()

print("Test complete - showing chunk visualization")
app.run()
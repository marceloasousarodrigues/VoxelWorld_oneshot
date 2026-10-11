import sys
sys.path.append('.')

from chunk import Chunk
import pytest

def test_chunk_refresh():
    # Create chunk and validate refresh can be called
    chunk = Chunk(0, 0, 0)  
    assert hasattr(chunk, 'refresh')
    
    # Verify it doesn't crash
    try:
        chunk.refresh()
    except Exception as e:
        pytest.fail(f"refresh() raised {type(e).__name__}: {e}")

def test_chunk_refresh_with_blocks():
    # Test refresh with actual block data 
    chunk = Chunk(0, 0, 0)
    
    # Set some blocks to generate geometry
    chunk.set_block(0, 0, 0, 1)  # Set a block type (should be solid)
    chunk.set_block(1, 0, 0, 1)
    
    chunk.refresh()
    assert len(chunk._mesh_vertices) > 0
    assert len(chunk._mesh_triangles) > 0
    initial_verts = len(chunk._mesh_vertices)

    # Break one block and verify mesh vertices decrease
    chunk.set_block(0, 0, 0, 0)
    chunk.refresh()
    assert len(chunk._mesh_vertices) < initial_verts

    # Break remaining block and verify mesh is empty
    chunk.set_block(1, 0, 0, 0)
    chunk.refresh()
    assert len(chunk._mesh_vertices) == 0


def test_chunk_refresh_updates_entity_mesh():
    from chunk_entity import create_chunk_entity
    from world import World
    from block_data import BlockType

    world = World()
    chunk = world.get_chunk(0, 0, 0)
    chunk.set_block(0, 0, 0, BlockType.DIRT)
    chunk.set_block(1, 0, 0, BlockType.DIRT)

    entity = create_chunk_entity(chunk, (0, 0, 0), world=world)
    assert entity.model is not None
    initial_verts = len(entity.model.vertices)

    # Modify block data in world and refresh
    world.set_block(0, 0, 0, BlockType.AIR)
    world.refresh()

    assert len(entity.model.vertices) < initial_verts

    # Break all blocks in chunk
    world.set_block(1, 0, 0, BlockType.AIR)
    world.refresh()

    assert entity.model is None
    assert entity.enabled == False
import sys
sys.path.append('.')

from world import World

def test_world_dirty_tracking():
    world = World()
    chunk_id = (0, 0, 0)
    assert chunk_id not in world.dirty_chunks
    
    # Mark chunk as dirty
    world.dirty(chunk_id)
    assert chunk_id in world.dirty_chunks
    
    # Refresh should clear the dirty set
    world.refresh()  
    assert chunk_id not in world.dirty_chunks

def test_world_set_block_marks_boundary_neighbor_dirty():
    from block_data import BlockType
    world = World()
    c1 = world.get_chunk(0, 0, 0)
    c2 = world.get_chunk(1, 0, 0)

    world.refresh()  # clear initial chunks dirty flags
    assert len(world.dirty_chunks) == 0

    # Block on the +X boundary of chunk (0,0,0) (local x=15)
    world.set_block(15, 0, 0, BlockType.DIRT)
    # Because neighbor chunk (1,0,0) is loaded, it should also be marked dirty
    assert (0, 0, 0) in world.dirty_chunks
    assert (1, 0, 0) in world.dirty_chunks

def test_cross_chunk_boundary_face_culling():
    from block_data import BlockType
    world = World()
    world.set_block(15, 0, 0, BlockType.DIRT)
    world.set_block(16, 0, 0, BlockType.DIRT)
    world.refresh()

    c1 = world.get_chunk(0, 0, 0)
    c2 = world.get_chunk(1, 0, 0)

    # Initial vertices on c1 for block 15 with neighbor solid block 16
    verts_c1_both = len(c1._mesh_vertices)

    # Break block 16 in neighbor chunk
    world.set_block(16, 0, 0, BlockType.AIR)
    world.refresh()

    verts_c1_air = len(c1._mesh_vertices)
    # c1 now exposes its +X face towards broken block 16, vertices count must increase
    assert verts_c1_air > verts_c1_both

if __name__ == "__main__":
    test_world_dirty_tracking()
    test_world_set_block_marks_boundary_neighbor_dirty()
    test_cross_chunk_boundary_face_culling()
    print("World dirty tracking test passed!")
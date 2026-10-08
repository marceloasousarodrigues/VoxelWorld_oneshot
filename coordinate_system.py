"""
Coordinate system utilities for VoxelWorld.
Handles conversion between world and chunk coordinates.
"""

# Chunk size constant (16x16x16 blocks per chunk)
CHUNK_SIZE = 16


def get_chunk_containing_world_coords(world_x: int, world_y: int, world_z: int) -> tuple[int, int, int]:
    """
    Convert world coordinates to chunk coordinates.
    
    This handles negative coordinates correctly by flooring division.
    
    Args:
        world_x: X coordinate in world space
        world_y: Y coordinate in world space
        world_z: Z coordinate in world space
        
    Returns:
        Tuple of (chunk_x, chunk_y, chunk_z) coordinates
    """
    # Use integer division to get chunk coordinates - this correctly implements floor division 
    # for both positive and negative numbers in Python
    chunk_x = world_x // CHUNK_SIZE
    chunk_y = world_y // CHUNK_SIZE  
    chunk_z = world_z // CHUNK_SIZE
    
    return (chunk_x, chunk_y, chunk_z)


def chunk_to_world_coords(chunk_x: int, chunk_y: int, chunk_z: int) -> tuple[int, int, int]:
    """
    Convert chunk coordinates to world coordinates for the chunk's origin.
    
    Args:
        chunk_x: X coordinate of the chunk
        chunk_y: Y coordinate of the chunk
        chunk_z: Z coordinate of the chunk
        
    Returns:
        Tuple of (world_x, world_y, world_z) coordinates of the chunk origin
    """
    return (
        chunk_x * CHUNK_SIZE,
        chunk_y * CHUNK_SIZE,
        chunk_z * CHUNK_SIZE
    )
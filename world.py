"""
World container for VoxelWorld.
Manages multiple chunks and coordinates generation, loading, unloading,
and updating of chunks.
"""

from collections import defaultdict
import numpy as np
from chunk import Chunk
from coordinate_system import get_chunk_containing_world_coords, chunk_to_world_coords
from block_data import BlockType


class World:
    """
    Manages the entire voxel world state including chunks.
    
    This class handles loading/unloading of chunks at runtime,
    maintaining world state for terrain generation, and provides 
    methods for world access and modification.
    """
    
    def __init__(self):
        """Initialize empty world."""
        # Dictionary to store loaded chunks by chunk coordinates
        self.chunks = {}
        
        # Store chunks that have been modified and need mesh regeneration
        self.dirty_chunks = set()
        
    def get_chunk(self, chunk_x: int, chunk_y: int, chunk_z: int) -> Chunk:
        """
        Get a chunk from the world, loading it if necessary.
        
        If a chunk is not already loaded, it will be created with default air blocks.
        
        Args:
            chunk_x: X coordinate of the chunk
            chunk_y: Y coordinate of the chunk  
            chunk_z: Z coordinate of the chunk
            
        Returns:
            Chunk object at the given coordinates
        """
        # Check if chunk is already loaded
        chunk_key = (chunk_x, chunk_y, chunk_z)
        if chunk_key in self.chunks:
            return self.chunks[chunk_key]
            
        # Create new chunk if needed
        new_chunk = Chunk(chunk_x, chunk_y, chunk_z)
        self.chunks[chunk_key] = new_chunk
        return new_chunk
        
    def get_block(self, world_x: int, world_y: int, world_z: int) -> int:
        """
        Get the block type at a world coordinate.
        
        Args:
            world_x: X coordinate in world space
            world_y: Y coordinate in world space
            world_z: Z coordinate in world space
            
        Returns:
            BlockType at the specified coordinates
        """
        # Convert to chunk and local coordinates
        chunk_x, chunk_y, chunk_z = get_chunk_containing_world_coords(world_x, world_y, world_z)
        local_x, local_y, local_z = world_x - (chunk_x * 16), world_y - (chunk_y * 16), world_z - (chunk_z * 16)
        
        # Get chunk and block data
        chunk = self.get_chunk(chunk_x, chunk_y, chunk_z)
        return int(chunk.get_block(local_x, local_y, local_z))
        
    def set_block(self, world_x: int, world_y: int, world_z: int, block_type: int) -> None:
        """
        Set the block type at a world coordinate.
        
        Args:
            world_x: X coordinate in world space
            world_y: Y coordinate in world space
            world_z: Z coordinate in world space
            block_type: BlockType to set at that location
        """
        # Convert to chunk and local coordinates
        chunk_x, chunk_y, chunk_z = get_chunk_containing_world_coords(world_x, world_y, world_z)
        local_x, local_y, local_z = world_x - (chunk_x * 16), world_y - (chunk_y * 16), world_z - (chunk_z * 16)
        
        # Get chunk and set block data
        chunk = self.get_chunk(chunk_x, chunk_y, chunk_z)
        chunk.set_block(local_x, local_y, local_z, block_type)
        
        # Mark the chunk as dirty (needs mesh regeneration)
        self.dirty_chunks.add((chunk_x, chunk_y, chunk_z))
        
    def get_chunk_coords_containing_world_coords(self, world_x: int, world_y: int, world_z: int) -> tuple[int, int, int]:
        """
        Get the chunk coordinates that contain the given world coordinates.
        
        Args:
            world_x: X coordinate in world space
            world_y: Y coordinate in world space
            world_z: Z coordinate in world space
            
        Returns:
            Tuple of (chunk_x, chunk_y, chunk_z) coordinates
        """
        return get_chunk_containing_world_coords(world_x, world_y, world_z)
        
    def generate_initial_terrain(self) -> None:
        """
        Generate initial terrain for the world.
        
        This creates a flat world with grass at the surface level (y=0),
        dirt below it, and stone below that. 
        """
        # Create a simple flattened world based on height levels
        # For this implementation we'll generate a deterministic flat terrain
        
        # Generate multiple chunks around origin to show terrain generation
        # In a real implementation, we'd have a larger world with more chunks
        for chunk_x in range(-1, 2):
            for chunk_z in range(-1, 2):
                chunk = self.get_chunk(chunk_x, 0, chunk_z)
                
                # Generate blocks in this chunk based on position
                for x in range(Chunk.SIZE_X):
                    for z in range(Chunk.SIZE_Z):
                        # Calculate world coordinates for this block
                        global_x = chunk_x * Chunk.SIZE_X + x
                        global_z = chunk_z * Chunk.SIZE_Z + z
                        
                        # For flat terrain, set blocks based on position
                        for y in range(Chunk.SIZE_Y):
                            if y == 0:
                                # Surface layer of grass (at y=15)
                                chunk.set_block(x, y, z, BlockType.GRASS)  # Grass at top
                            elif y < 5:
                                # Dirt layer (4 layers below)
                                chunk.set_block(x, y, z, BlockType.DIRT)  # Dirt
                            elif y < 16:
                                # Stone layer at bottom
                                chunk.set_block(x, y, z, BlockType.STONE)  # Stone
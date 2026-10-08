"""
Chunk class for VoxelWorld.
Represents a 16x16x16 block section of the world.
"""

import numpy as np
from block_data import BlockType


class Chunk:
    """
    Represents a 16x16x16 voxel chunk.
    
    Chunks are the fundamental building blocks of the world.
    Each chunk stores its own block data and can be rendered independently.
    """
    
    SIZE_X = 16
    SIZE_Y = 16  
    SIZE_Z = 16
    
    def __init__(self, chunk_x: int, chunk_y: int, chunk_z: int):
        """Initialize an empty chunk."""
        self.chunk_x = chunk_x
        self.chunk_y = chunk_y
        self.chunk_z = chunk_z
        
        # Initialize all blocks to air
        self.blocks = np.full((Chunk.SIZE_X, Chunk.SIZE_Y, Chunk.SIZE_Z), BlockType.AIR)
        
    def get_block(self, x: int, y: int, z: int) -> int:
        """
        Get the block type at local coordinates within this chunk.
        
        Args:
            x: X coordinate (0-15)
            y: Y coordinate (0-15)
            z: Z coordinate (0-15)
            
        Returns:
            BlockType at the specified coordinates
        """
        return self.blocks[x, y, z]
        
    def set_block(self, x: int, y: int, z: int, block_type: int) -> None:
        """
        Set the block type at local coordinates within this chunk.
        
        Args:
            x: X coordinate (0-15)
            y: Y coordinate (0-15)
            z: Z coordinate (0-15)
            block_type: BlockType to set
        """
        self.blocks[x, y, z] = block_type

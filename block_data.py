"""
Block data definitions for VoxelWorld.
Defines block types and their properties.
"""

from enum import IntEnum


class BlockType(IntEnum):
    """
    Enum representing different block types in the game world.
    
    Each block type has a unique ID that can be used to identify it.
    """
    AIR = 0
    GRASS = 1
    DIRT = 2
    STONE = 3
    WATER = 4
    SAND = 5


# Block properties dictionary
BLOCK_PROPERTIES = {
    BlockType.AIR: {
        'name': 'Air',
        'is_solid': False,
        'texture': None
    },
    BlockType.GRASS: {
        'name': 'Grass',
        'is_solid': True,
        'texture': 'grass.png'
    },
    BlockType.DIRT: {
        'name': 'Dirt',  
        'is_solid': True,
        'texture': 'dirt.png'
    },
    BlockType.STONE: {
        'name': 'Stone',
        'is_solid': True,
        'texture': 'stone.png'
    },
    BlockType.WATER: {
        'name': 'Water',
        'is_solid': False,  # Water is not solid - you can walk through it
        'texture': 'water.png'
    },
    BlockType.SAND: {
        'name': 'Sand',
        'is_solid': True,
        'texture': 'sand.png'
    }
}


def is_block_solid(block_type: int) -> bool:
    """
    Check if a block type is solid (cannot be walked through).
    
    Args:
        block_type: BlockType to check
        
    Returns:
        True if the block is solid, False otherwise
    """
    return BLOCK_PROPERTIES[block_type]['is_solid']


def get_block_texture(block_type: int) -> str:
    """
    Get the texture name for a block type.
    
    Args:
        block_type: BlockType to get texture for
        
    Returns:
        Texture filename string or None if no texture
    """
    return BLOCK_PROPERTIES[block_type]['texture']

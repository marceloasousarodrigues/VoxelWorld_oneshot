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
        'texture': None,
        'top_texture': None,
        'side_texture': None,
        'bottom_texture': None,
        'is_transparent': False,
    },
    BlockType.GRASS: {
        'name': 'Grass',
        'is_solid': True,
        'texture': 'grass.png',
        'top_texture': 'voxel_textures/blocks/grass_top.png',
        'side_texture': 'voxel_textures/blocks/grass_side.png',
        'bottom_texture': 'voxel_textures/blocks/dirt.png',
        'is_transparent': False,
    },
    BlockType.DIRT: {
        'name': 'Dirt',
        'is_solid': True,
        'texture': 'dirt.png',
        'top_texture': 'voxel_textures/blocks/dirt.png',
        'side_texture': 'voxel_textures/blocks/dirt.png',
        'bottom_texture': 'voxel_textures/blocks/dirt.png',
        'is_transparent': False,
    },
    BlockType.STONE: {
        'name': 'Stone',
        'is_solid': True,
        'texture': 'stone.png',
        'top_texture': 'voxel_textures/blocks/stone_generic.png',
        'side_texture': 'voxel_textures/blocks/stone_generic.png',
        'bottom_texture': 'voxel_textures/blocks/stone_generic.png',
        'is_transparent': False,
    },
    BlockType.WATER: {
        'name': 'Water',
        'is_solid': False,
        'texture': 'water.png',
        'top_texture': 'voxel_textures/blocks/water.png',
        'side_texture': 'voxel_textures/blocks/water.png',
        'bottom_texture': 'voxel_textures/blocks/water.png',
        'is_transparent': True,
    },
    BlockType.SAND: {
        'name': 'Sand',
        'is_solid': True,
        'texture': 'sand.png',
        'top_texture': 'voxel_textures/blocks/sand_ugly.png',
        'side_texture': 'voxel_textures/blocks/sand_ugly.png',
        'bottom_texture': 'voxel_textures/blocks/sand_ugly.png',
        'is_transparent': False,
    },
}


def is_block_solid(block_type: int) -> bool:
    """Check if a block type is solid (cannot be walked through)."""
    return BLOCK_PROPERTIES[block_type]['is_solid']


def get_block_face_textures(block_type: int) -> dict:
    props = BLOCK_PROPERTIES[block_type]
    return {
        'top': props.get('top_texture'),
        'side': props.get('side_texture'),
        'bottom': props.get('bottom_texture'),
    }


def is_block_transparent(block_type: int) -> bool:
    return BLOCK_PROPERTIES[block_type].get('is_transparent', False)


def get_block_texture(block_type: int) -> str:
    """Backward-compatible texture lookup (legacy non-face-aware path).

    Returns the block's legacy texture filename, or None.
    """
    return BLOCK_PROPERTIES[block_type]['texture']

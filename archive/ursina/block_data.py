"""
Block data definitions for VoxelWorld.
Defines block types and their properties.
"""

from enum import IntEnum

import numpy as np

from texture_config import block_face_textures


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
    OAK_LOG = 6
    OAK_LEAVES = 7


# Block properties dictionary. Per-face texture paths are populated from the
# centralized texture configuration (config/texture_manifest.json) so the
# manifest stays the single source of truth; only the legacy short `texture`
# name is declared here.
BLOCK_PROPERTIES = {
    BlockType.AIR: {
        'name': 'Air',
        'is_solid': False,
        'texture': None,
        'is_transparent': False,
    },
    BlockType.GRASS: {
        'name': 'Grass',
        'is_solid': True,
        'texture': 'grass.png',
        'is_transparent': False,
    },
    BlockType.DIRT: {
        'name': 'Dirt',
        'is_solid': True,
        'texture': 'dirt.png',
        'is_transparent': False,
    },
    BlockType.STONE: {
        'name': 'Stone',
        'is_solid': True,
        'texture': 'stone.png',
        'is_transparent': False,
    },
    BlockType.WATER: {
        'name': 'Water',
        'is_solid': False,
        'texture': 'water.png',
        'is_transparent': True,
    },
    BlockType.SAND: {
        'name': 'Sand',
        'is_solid': True,
        'texture': 'sand.png',
        'is_transparent': False,
    },
    # M14 vegetation. Leaves are solid and opaque-pass blocks: their cutout holes
    # come from the alpha-test material on the opaque chunk entity (spec D3/D6),
    # not from the transparent pass, so face culling and collision stay identical
    # to every other solid block.
    BlockType.OAK_LOG: {
        'name': 'Oak Log',
        'is_solid': True,
        'texture': 'default_tree.png',
        'is_transparent': False,
    },
    BlockType.OAK_LEAVES: {
        'name': 'Oak Leaves',
        'is_solid': True,
        'texture': 'default_leaves.png',
        'is_transparent': False,
    },
}

for _block_type, _properties in BLOCK_PROPERTIES.items():
    _faces = block_face_textures(_block_type.name)
    _properties['top_texture'] = _faces['top']
    _properties['side_texture'] = _faces['side']
    _properties['bottom_texture'] = _faces['bottom']


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


# Block types that belong to the transparent render pass. Exposed as a tuple so a
# whole chunk can be tested in one vectorised operation instead of 4096 scalar
# reads (M16 stutter fix: the per-cell scan cost 4.33 ms of a 26 ms chunk load).
TRANSPARENT_BLOCK_TYPES = tuple(
    int(block_type)
    for block_type, properties in BLOCK_PROPERTIES.items()
    if properties.get('is_transparent', False)
)


def has_transparent_block(blocks) -> bool:
    """True when a block array contains at least one transparent-pass block.

    Equivalent to scanning every cell with ``is_block_transparent`` (the tests
    pin that equivalence against the previous triple loop), but one vectorised
    comparison for the whole array instead of one numpy scalar read per cell.
    Unknown or out-of-range block values simply compare unequal, so no indexing
    hazard is introduced.

    Args:
        blocks: The chunk's ``(SIZE_X, SIZE_Y, SIZE_Z)`` block array

    Returns:
        Whether any cell holds a transparent block
    """
    return bool(np.isin(blocks, TRANSPARENT_BLOCK_TYPES).any())


def get_block_texture(block_type: int) -> str:
    """Backward-compatible texture lookup (legacy non-face-aware path).

    Returns the block's legacy texture filename, or None.
    """
    return BLOCK_PROPERTIES[block_type]['texture']

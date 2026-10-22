"""
Texture management for VoxelWorld.

Lazily loads 2D face textures for each block type and caches them, so they
are only read from disk (and compiled by Ursina) once per block.

M7 rendering relies on this: chunk faces are textured with the matching
BlockType texture when available, and fall back to the procedural face color
otherwise.
"""

from __future__ import annotations

from block_data import BlockType, get_block_texture
from ursina import Texture, color


# Registry of loaded textures keyed by block enum. Populated the first time
# each block texture is requested so we do not hit disk repeatedly.
_TEXTURE_CACHE: dict[BlockType, Texture] = {}


def get_texture(block_type: BlockType) -> Texture | None:
    """
    Return the cached Texture for a block type, loading it on first use.

    Args:
        block_type: The block type to fetch a texture for.

    Returns:
        The loaded ursina Texture, or None if the block has no texture
        defined (e.g. AIR).
    """
    if block_type in _TEXTURE_CACHE:
        return _TEXTURE_CACHE[block_type]

    _TEXTURE_CACHE[block_type] = _load(block_type)
    return _TEXTURE_CACHE[block_type]


def _load(block_type: BlockType) -> Texture | None:
    """
    Load a block texture from disk. Returns None if it cannot be found.
    """
    texture_name = get_block_texture(int(block_type))
    if texture_name is None:
        return None
    try:
        return Texture(texture_name)
    except Exception:
        return None


def get_color(block_type: BlockType) -> color.Color:
    """
    Return the procedural face color for a block type.

    This is the fallback applied when a face is occluded (and thus untextured).

    Args:
        block_type: The block type to get a color for.

    Returns:
        A ursina color.Color instance.
    """
    return _FACE_COLORS.get(block_type, color.rgb(128, 128, 128))


def has_texture(block_type: BlockType) -> bool:
    """Return whether a texture can be found for the block type."""
    return get_texture(block_type) is not None


def reset() -> None:
    """Clear the texture cache and reset cached colors for test isolation."""
    _TEXTURE_CACHE.clear()
    _FACE_COLORS.clear()
    _FACE_COLORS.update({
        BlockType.GRASS: color.rgb(76, 153, 50),
        BlockType.DIRT: color.rgb(139, 90, 43),
        BlockType.STONE: color.rgb(128, 128, 128),
        BlockType.WATER: color.rgb(53, 120, 200),
        BlockType.SAND: color.rgb(222, 205, 145),
        BlockType.AIR: color.rgb(39, 39, 39),
    })


# Procedural face colors per block (fallback when faces are occluded).
_FACE_COLORS: dict[BlockType, color.Color] = {}


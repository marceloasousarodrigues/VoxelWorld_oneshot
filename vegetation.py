"""
Deterministic vegetation generation for VoxelWorld (M14).

This module is deliberately Ursina-free so it can be imported and tested
headlessly.

Every generation decision is a pure function of ``(seed, world coordinates)``.
No code here calls Python's builtin ``hash()`` (salted per process) or the
``random`` module, so identical seeds produce identical worlds regardless of
chunk generation order, load order or process.
"""

# Decoration layer values stored in ``Chunk.decorations``.
DECORATION_NONE = 0
GRASS_TUFT_VARIANTS = 5

# Placement tuning.
GRASS_DENSITY_PERCENT = 30

# Domain separators so one world column can drive several independent choices.
PLANT_SALT = 1
VARIANT_SALT = 2

UINT32_MASK = 0xFFFFFFFF
UINT64_MASK = 0xFFFFFFFFFFFFFFFF

# splitmix64 constants.
_GOLDEN = 0x9E3779B97F4A7C15
_MIX_A = 0xBF58476D1CE4E5B9
_MIX_B = 0x94D049BB133111EB

# Per-channel odd multipliers used to fold the four inputs together before
# mixing, so that e.g. (x=1, z=0) and (x=0, z=1) cannot collide.
_SALT_MUL_SEED = 0x9E3779B1
_SALT_MUL_X = 0x85EBCA77
_SALT_MUL_Z = 0xC2B2AE3D
_SALT_MUL_SALT = 0x27D4EB2F


def _mix64(value: int) -> int:
    """Finalize a 64-bit accumulator with the splitmix64 mixer."""
    value = (value + _GOLDEN) & UINT64_MASK
    value = ((value ^ (value >> 30)) * _MIX_A) & UINT64_MASK
    value = ((value ^ (value >> 27)) * _MIX_B) & UINT64_MASK
    return (value ^ (value >> 31)) & UINT64_MASK


def hash32(seed: int, x: int, z: int, salt: int = 0) -> int:
    """
    Deterministic 32-bit hash of ``(seed, x, z, salt)``.

    Explicit 32-bit arithmetic over a 64-bit accumulator, so negative
    coordinates and negative salts are handled uniformly and the result is
    identical in every process.

    Args:
        seed: World seed
        x: X world coordinate
        z: Z world coordinate
        salt: Domain separator so one coordinate can serve several decisions

    Returns:
        Integer in ``[0, 2**32)``
    """
    combined = (
        ((seed & UINT32_MASK) * _SALT_MUL_SEED)
        ^ ((x & UINT32_MASK) * _SALT_MUL_X)
        ^ ((z & UINT32_MASK) * _SALT_MUL_Z)
        ^ ((salt & UINT32_MASK) * _SALT_MUL_SALT)
    ) & UINT64_MASK
    return _mix64(combined) & UINT32_MASK


def grass_variant_for_column(seed: int, x: int, z: int) -> int:
    """
    Decoration value for a world column: ``DECORATION_NONE`` or a tuft variant.

    Pure and order-independent: depends only on the column's own world
    coordinates and the seed.

    Args:
        seed: World seed
        x: X world coordinate of the column
        z: Z world coordinate of the column

    Returns:
        ``0`` when no tuft is placed, otherwise ``1..GRASS_TUFT_VARIANTS``
    """
    if hash32(seed, x, z, PLANT_SALT) % 100 >= GRASS_DENSITY_PERCENT:
        return DECORATION_NONE
    return 1 + hash32(seed, x, z, VARIANT_SALT) % GRASS_TUFT_VARIANTS


def generate_vegetation_for_chunk(chunk, seed: int) -> None:
    """
    Populate a single chunk's vegetation (spec D5).

    Only the ground-level chunk layer (``chunk_y == 0``) carries terrain, so
    only that layer carries vegetation.

    Args:
        chunk: The Chunk to populate
        seed: World seed
    """
    if chunk.chunk_y != 0:
        return

    _generate_tufts_for_chunk(chunk, seed)


def _generate_tufts_for_chunk(chunk, seed: int) -> None:
    """Place grass tufts into a chunk's decoration layer (spec D5).

    Tufts are written into ``chunk.decorations`` only; the block grid is never
    modified, so they cannot affect collision, raycast, placement or water.
    """
    from block_data import BlockType
    from terrain_generation import in_lake, surface_height

    size_x = chunk.SIZE_X
    size_y = chunk.SIZE_Y
    size_z = chunk.SIZE_Z
    base_x = chunk.chunk_x * size_x
    base_z = chunk.chunk_z * size_z

    for x in range(size_x):
        for z in range(size_z):
            gx = base_x + x
            gz = base_z + z

            # Never place vegetation over the lake.
            if in_lake(gx, gz):
                continue

            surface = surface_height(seed, gx, gz)
            y = surface + 1

            # No room for a tuft inside this chunk layer.
            if y > size_y - 1:
                continue

            # Require exposed grass: the surface block is GRASS and the cell
            # above is AIR. This also keeps tufts out of trees, which are
            # written as solid blocks before tufts are placed.
            if chunk.get_block(x, surface, z) != BlockType.GRASS:
                continue
            if chunk.get_block(x, y, z) != BlockType.AIR:
                continue

            variant = grass_variant_for_column(seed, gx, gz)
            if variant != DECORATION_NONE:
                chunk.set_decoration(x, y, z, variant)

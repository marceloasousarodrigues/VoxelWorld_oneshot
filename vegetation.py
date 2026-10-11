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

# Tree grid (spec D7/D7.1). TREE_GRID = 6 deliberately does not divide
# CHUNK_SIZE = 16, so grid cells — and therefore tree footprints — straddle chunk
# boundaries. TREE_JITTER_MAX = 3 is the largest jitter that still keeps every
# footprint inside its own grid cell:
#   TREE_JITTER_MIN - CANOPY_RADIUS = 0 >= 0
#   TREE_JITTER_MAX + CANOPY_RADIUS = 5 <= TREE_GRID - 1
TREE_GRID = 6
TREE_JITTER_MIN = 2
TREE_JITTER_MAX = 3
TREE_DENSITY_PERCENT = 35
CANOPY_RADIUS = 2
TREE_MIN_HEIGHT = 4
TREE_HEIGHT_RANGE = 3

# Domain separators so one world column can drive several independent choices.
PLANT_SALT = 1
VARIANT_SALT = 2
TREE_SALT = 3
JITTER_X_SALT = 4
JITTER_Z_SALT = 5
HEIGHT_SALT = 6
CANOPY_TOP_SALT = 7

from coordinate_system import CHUNK_SIZE

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


def tree_candidate(grid_x: int, grid_z: int, seed: int):
    """
    Deterministic tree anchor for one ``TREE_GRID`` cell, or ``None`` (spec D7).

    The anchor is the grid cell's origin jittered by ``hash32`` into
    ``[TREE_JITTER_MIN, TREE_JITTER_MAX]`` on each axis, which keeps the whole
    footprint inside the cell (D7.1). Purely a function of the grid cell and the
    seed: no chunk or world access, no neighbouring-chunk read.

    Args:
        grid_x: X index of the TREE_GRID cell
        grid_z: Z index of the TREE_GRID cell
        seed: World seed

    Returns:
        Dict with ``grid_x``, ``grid_z``, ``origin_x``, ``origin_z``,
        ``surface`` and ``height``, or ``None`` when no tree grows there
    """
    from terrain_generation import (
        LAKE_CENTER_X,
        LAKE_CENTER_Z,
        LAKE_RADIUS,
        in_lake,
        surface_height,
    )

    jitter_span = TREE_JITTER_MAX - TREE_JITTER_MIN + 1
    origin_x = grid_x * TREE_GRID + TREE_JITTER_MIN + (
        hash32(seed, grid_x, grid_z, JITTER_X_SALT) % jitter_span
    )
    origin_z = grid_z * TREE_GRID + TREE_JITTER_MIN + (
        hash32(seed, grid_x, grid_z, JITTER_Z_SALT) % jitter_span
    )

    if hash32(seed, origin_x, origin_z, TREE_SALT) % 100 >= TREE_DENSITY_PERCENT:
        return None

    # Never in the lake, and never close enough for the canopy to hang over it.
    if in_lake(origin_x, origin_z):
        return None
    clearance = LAKE_RADIUS + CANOPY_RADIUS + 1
    if (origin_x - LAKE_CENTER_X) ** 2 + (origin_z - LAKE_CENTER_Z) ** 2 < clearance ** 2:
        return None

    surface = surface_height(seed, origin_x, origin_z)
    height = TREE_MIN_HEIGHT + (
        hash32(seed, origin_x, origin_z, HEIGHT_SALT) % TREE_HEIGHT_RANGE
    )

    # The whole tree, including the top canopy layer, must fit in this chunk
    # layer. Only chunk_y == 0 carries terrain.
    if surface + height + 1 > CHUNK_SIZE - 1:
        return None

    return {
        "grid_x": grid_x,
        "grid_z": grid_z,
        "origin_x": origin_x,
        "origin_z": origin_z,
        "surface": surface,
        "height": height,
    }


def _canopy_offsets():
    """5x5 footprint minus its four corners, relative to the anchor."""
    r = CANOPY_RADIUS
    return tuple(
        (dx, dz)
        for dx in range(-r, r + 1)
        for dz in range(-r, r + 1)
        if not (abs(dx) == r and abs(dz) == r)
    )


def tree_blocks(
    origin_x: int, origin_z: int, surface: int, height: int, seed: int
) -> list:
    """
    Solid blocks of one tree, trunk first (spec D7).

    Returns ``(x, y, z, BlockType)`` tuples in a deterministic order, with every
    cell appearing at most once: the trunk is emitted first and wins wherever a
    canopy layer would otherwise overlap it. Cells that would be buried in
    terrain (``y <= surface_height``) or sit over the lake are omitted.

    Args:
        origin_x: X world coordinate of the trunk column
        origin_z: Z world coordinate of the trunk column
        surface: Surface height at the anchor (trunk starts at ``surface + 1``)
        height: Trunk height
        seed: World seed

    Returns:
        List of ``(x, y, z, BlockType)``
    """
    from block_data import BlockType
    from terrain_generation import in_lake, surface_height

    cells = {}

    def add(cx: int, cy: int, cz: int, block) -> None:
        """Record an intended tree cell only where it can legally stand."""
        if cy < 0 or cy > CHUNK_SIZE - 1:
            return
        if in_lake(cx, cz):
            return
        if cy <= surface_height(seed, cx, cz):
            return
        cells.setdefault((cx, cy, cz), block)

    # Trunk: 1x1 column from surface + 1 to surface + height.
    for offset in range(1, height + 1):
        add(origin_x, surface + offset, origin_z, BlockType.OAK_LOG)

    # Canopy layers, relative to the trunk base.
    for layer in (height - 2, height - 1):
        for dx, dz in _canopy_offsets():
            add(origin_x + dx, surface + layer, origin_z + dz, BlockType.OAK_LEAVES)

    for dx in (-1, 0, 1):
        for dz in (-1, 0, 1):
            add(origin_x + dx, surface + height, origin_z + dz, BlockType.OAK_LEAVES)

    if hash32(seed, origin_x, origin_z, CANOPY_TOP_SALT) % 2 == 0:
        top_offsets = ((0, 0), (-1, 0), (1, 0), (0, -1), (0, 1))
    else:
        top_offsets = ((0, 0),)
    for dx, dz in top_offsets:
        add(origin_x + dx, surface + height + 1, origin_z + dz, BlockType.OAK_LEAVES)

    return [(cx, cy, cz, block) for (cx, cy, cz), block in cells.items()]


def cell_owner(cx: int, cy: int, cz: int, seed: int):
    """
    Owning ``(grid_x, grid_z)`` for a world cell, or ``None`` (spec D7.2).

    By the D7.1 containment lemma every footprint is a subset of its own grid
    cell, so the owner reduces to the closed form ``(cx // TREE_GRID,
    cz // TREE_GRID)`` using floor division, which is correct for negative
    coordinates. ``None`` means the owning grid cell holds no tree. This is a
    total, order-independent rule computed from the cell's own coordinates, so it
    never depends on which chunk is generated first.

    Args:
        cx: X world coordinate of the cell
        cy: Y world coordinate of the cell
        cz: Z world coordinate of the cell
        seed: World seed

    Returns:
        ``(grid_x, grid_z)`` of the owning candidate, or ``None``
    """
    grid_x = cx // TREE_GRID
    grid_z = cz // TREE_GRID
    if tree_candidate(grid_x, grid_z, seed) is None:
        return None
    return (grid_x, grid_z)


def tree_owns_cell(candidate, cx: int, cy: int, cz: int, seed: int) -> bool:
    """
    Whether ``candidate`` is the owner of world cell ``(cx, cy, cz)`` (spec D7.2).

    Args:
        candidate: A dict from ``tree_candidate``
        cx: X world coordinate of the cell
        cy: Y world coordinate of the cell
        cz: Z world coordinate of the cell
        seed: World seed

    Returns:
        True when this candidate is the cell's one and only owner
    """
    return cell_owner(cx, cy, cz, seed) == (candidate["grid_x"], candidate["grid_z"])


def tree_scan_cells(chunk_x: int, chunk_z: int):
    """
    TREE_GRID cells whose footprints can intersect one chunk (spec D8).

    ``TREE_GRID = 6`` does not divide ``CHUNK_SIZE = 16``, so a footprint can
    straddle a boundary and reach into the neighbouring grid cell. The scan is
    padded by one cell on each side.

    Args:
        chunk_x: X index of the chunk
        chunk_z: Z index of the chunk

    Returns:
        Iterator of ``(grid_x, grid_z)`` pairs
    """
    min_x = chunk_x * CHUNK_SIZE
    min_z = chunk_z * CHUNK_SIZE
    max_x = min_x + CHUNK_SIZE - 1
    max_z = min_z + CHUNK_SIZE - 1
    for grid_x in range(min_x // TREE_GRID - 1, max_x // TREE_GRID + 2):
        for grid_z in range(min_z // TREE_GRID - 1, max_z // TREE_GRID + 2):
            yield grid_x, grid_z


def generate_vegetation_for_chunk(chunk, seed: int) -> None:
    """
    Populate a single chunk's vegetation (spec D5 and D7).

    Trees are written before tufts so a tuft is never placed inside a trunk, and
    only the ground-level chunk layer (``chunk_y == 0``) carries terrain, so only
    that layer carries vegetation.

    Args:
        chunk: The Chunk to populate
        seed: World seed
    """
    if chunk.chunk_y != 0:
        return

    _generate_trees_for_chunk(chunk, seed)
    _generate_tufts_for_chunk(chunk, seed)


def _generate_trees_for_chunk(chunk, seed: int) -> None:
    """Write the tree blocks owned by this chunk (spec D7).

    A chunk writes only the cells it holds and owns, and only into ``AIR``, so no
    terrain or water block is ever replaced and the result does not depend on the
    order chunks are generated in.
    """
    from block_data import BlockType

    size_x = chunk.SIZE_X
    size_y = chunk.SIZE_Y
    size_z = chunk.SIZE_Z
    base_x = chunk.chunk_x * size_x
    base_z = chunk.chunk_z * size_z

    for grid_x, grid_z in tree_scan_cells(chunk.chunk_x, chunk.chunk_z):
        candidate = tree_candidate(grid_x, grid_z, seed)
        if candidate is None:
            continue

        for cx, cy, cz, block in tree_blocks(
            candidate["origin_x"],
            candidate["origin_z"],
            candidate["surface"],
            candidate["height"],
            seed,
        ):
            if not tree_owns_cell(candidate, cx, cy, cz, seed):
                continue

            local_x = cx - base_x
            local_y = cy  # chunk_y == 0
            local_z = cz - base_z
            if not (0 <= local_x < size_x):
                continue
            if not (0 <= local_y < size_y):
                continue
            if not (0 <= local_z < size_z):
                continue

            if chunk.get_block(local_x, local_y, local_z) != BlockType.AIR:
                continue

            chunk.set_block(local_x, local_y, local_z, block)
            chunk.clear_decoration(local_x, local_y, local_z)


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

"""
Raycasting utilities for VoxelWorld.
Handles raycast operations from player camera into the voxel world.
"""

import math

from block_data import is_block_solid


def _is_solid(block_type):
    """
    Return True when a block value blocks the ray.

    Uses the block data table so non-solid types (e.g. AIR, WATER) are
    passed through. Falls back to "non-zero means solid" for unknown
    block values.
    """

    if block_type is None:
        return False

    try:
        return is_block_solid(block_type)
    except (KeyError, IndexError, TypeError):
        return block_type != 0


def raycast(origin, direction, world, max_range=6.0):
    """
    Cast a ray into the world and return the first solid block hit.

    The ray is walked voxel-by-voxel using an Amanatides & Woo grid
    traversal (a DDA variant). Block lookup goes through
    ``world.get_block`` so chunk boundaries are resolved by the World and
    the result is independent of chunk load state.

    Args:
        origin: Starting position of the ray (x, y, z).
        direction: Ray direction vector (x, y, z). Need not be normalized.
        world: World object exposing ``get_block(world_x, world_y, world_z)``.
        max_range: Maximum distance, in world units, to cast.

    Returns:
        dict or None. The dict contains:
            'position': (int, int, int) world position of the hit block.
            'block_type': int block type at that position.
            'face': (int, int, int) outward normal of the hit face, or
                None when the ray origin starts inside a solid block.
            'neighbor_pos': (int, int, int) world position adjacent to the
                hit face (``position + face``), or None when ``face`` is None.
        Returns None when no solid block is hit within ``max_range``.
    """

    length = math.sqrt(direction[0] ** 2 + direction[1] ** 2 + direction[2] ** 2)
    if length == 0:
        return None

    dir_x = direction[0] / length
    dir_y = direction[1] / length
    dir_z = direction[2] / length

    ox, oy, oz = origin[0], origin[1], origin[2]

    # Voxel currently containing the ray origin.
    cell_x = math.floor(ox)
    cell_y = math.floor(oy)
    cell_z = math.floor(oz)

    # Unit step per axis.
    step_x = 1 if dir_x > 0 else (-1 if dir_x < 0 else 0)
    step_y = 1 if dir_y > 0 else (-1 if dir_y < 0 else 0)
    step_z = 1 if dir_z > 0 else (-1 if dir_z < 0 else 0)

    # Parametric distance to cross one full voxel along each axis.
    t_delta_x = abs(1.0 / dir_x) if dir_x != 0 else float('inf')
    t_delta_y = abs(1.0 / dir_y) if dir_y != 0 else float('inf')
    t_delta_z = abs(1.0 / dir_z) if dir_z != 0 else float('inf')

    # Parametric distance to the first voxel boundary along each axis.
    if dir_x > 0:
        t_max_x = (cell_x + 1 - ox) / dir_x
    elif dir_x < 0:
        t_max_x = (cell_x - ox) / dir_x
    else:
        t_max_x = float('inf')

    if dir_y > 0:
        t_max_y = (cell_y + 1 - oy) / dir_y
    elif dir_y < 0:
        t_max_y = (cell_y - oy) / dir_y
    else:
        t_max_y = float('inf')

    if dir_z > 0:
        t_max_z = (cell_z + 1 - oz) / dir_z
    elif dir_z < 0:
        t_max_z = (cell_z - oz) / dir_z
    else:
        t_max_z = float('inf')

    t = 0.0
    face = None

    # Bounded: each step advances t by at least one t_delta, and the loop
    # exits once t exceeds max_range, but a hard cap protects against any
    # pathological input.
    for _ in range(1000):
        if t > max_range:
            return None

        block_type = world.get_block(cell_x, cell_y, cell_z)

        if _is_solid(block_type):
            neighbor_pos = None
            if face is not None:
                neighbor_pos = (
                    cell_x + face[0],
                    cell_y + face[1],
                    cell_z + face[2],
                )

            return {
                'position': (cell_x, cell_y, cell_z),
                'block_type': block_type,
                'face': face,
                'neighbor_pos': neighbor_pos,
            }

        # Advance to the neighbouring voxel across the nearest boundary.
        # The face normal is opposite the step direction, so it points
        # back toward the ray origin.
        if t_max_x < t_max_y and t_max_x < t_max_z:
            t = t_max_x
            t_max_x += t_delta_x
            cell_x += step_x
            face = (-step_x, 0, 0)
        elif t_max_y < t_max_z:
            t = t_max_y
            t_max_y += t_delta_y
            cell_y += step_y
            face = (0, -step_y, 0)
        else:
            t = t_max_z
            t_max_z += t_delta_z
            cell_z += step_z
            face = (0, 0, -step_z)

    return None

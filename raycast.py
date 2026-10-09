"""
Raycasting functionality for VoxelWorld.
Handles interaction point determination via raycasting into the world.
"""

import math
from coordinate_system import CHUNK_SIZE


def raycast(origin, direction, world, max_range=6.0):
    """
    Cast a ray into the world and return first solid block hit.
    
    Args:
        origin: Starting position of the ray (x, y, z)
        direction: Ray direction (x, y, z), should be normalized
        world: World object to raycast against
        max_range: Maximum distance to raycast
        
    Returns:
        Dictionary with hit information or None if no block hit within range
    """
    # Normalize the direction vector
    length = math.sqrt(direction[0]**2 + direction[1]**2 + direction[2]**2)
    if length > 0:
        direction = (direction[0]/length, direction[1]/length, direction[2]/length)
    
    # For simplicity in this implementation, we'll implement a basic DDA approach
    # that steps through voxel cells along the ray
    pos = list(origin)
    step_x = 1 if direction[0] >= 0 else -1
    step_y = 1 if direction[1] >= 0 else -1
    step_z = 1 if direction[2] >= 0 else -1
    
    # Distance to next voxel boundary in each direction
    t_delta_x = abs(1.0 / direction[0]) if direction[0] != 0 else float('inf')
    t_delta_y = abs(1.0 / direction[1]) if direction[1] != 0 else float('inf')
    t_delta_z = abs(1.0 / direction[2]) if direction[2] != 0 else float('inf')
    
    # Current voxel coordinates
    voxel_x = int(pos[0])
    voxel_y = int(pos[1]) 
    voxel_z = int(pos[2])
    
    t_max_x = (1.0 + (1 if step_x > 0 else 0) - (pos[0] - voxel_x)) * t_delta_x if direction[0] != 0 else float('inf')
    t_max_y = (1.0 + (1 if step_y > 0 else 0) - (pos[1] - voxel_y)) * t_delta_y if direction[1] != 0 else float('inf')
    t_max_z = (1.0 + (1 if step_z > 0 else 0) - (pos[2] - voxel_z)) * t_delta_z if direction[2] != 0 else float('inf')
    
    distance = 0.0
    
    # Step along the ray until max_range is reached or we hit a solid block 
    while distance < max_range:
        # Check if current voxel position is within world bounds
        block_type = world.get_block(voxel_x, voxel_y, voxel_z)
        
        # If we found a solid block, return it
        if block_type != 0:  # 0 is AIR
            # Return hit information
            return {
                'position': (voxel_x, voxel_y, voxel_z),
                'block_type': block_type,
                'face': _get_hit_face(voxel_x, voxel_y, voxel_z, pos)
            }
            
        # Move to next voxel boundary
        if t_max_x <= t_max_y and t_max_x <= t_max_z:
            # Step in x direction
            voxel_x += step_x
            distance += t_delta_x
            t_max_x += t_delta_x
        elif t_max_y <= t_max_z:
            # Step in y direction
            voxel_y += step_y
            distance += t_delta_y
            t_max_y += t_delta_y
        else:
            # Step in z direction
            voxel_z += step_z
            distance += t_delta_z
            t_max_z += t_delta_z
            
    return None  # No hit within range


def _get_hit_face(voxel_x, voxel_y, voxel_z, ray_pos):
    """
    Determine which face of a block was hit.
    
    Args:
        voxel_x, voxel_y, voxel_z: Coordinates of the hit voxel
        ray_pos: Position where the ray started
        
    Returns:
        Face information (simplified for this implementation)
    """
    # Simple implementation - return a basic face direction
    return 'front'  # In a more complete implementation, would determine actual face
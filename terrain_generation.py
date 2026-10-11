"""
Terrain generation module for VoxelWorld.
Generates natural-looking terrain using noise functions and height maps.
"""

import math
import random
from world import World  
from chunk import Chunk
from block_data import BlockType, is_block_solid


# M14: the lake geometry is a deterministic circle. These constants and the
# height function are exposed at module level so vegetation generation can
# decide "is this a grass surface / is this water" from pure functions instead
# of reading generated chunk data.
LAKE_CENTER_X = 0
LAKE_CENTER_Z = 0
LAKE_RADIUS = 6
LAKE_FLOOR = 2
LAKE_LEVEL = 4

BASE_HEIGHT = 6
MIN_HEIGHT = 0
MAX_HEIGHT = 15


def _noise(x: float, z: float) -> float:
    """
    Simple noise function using sine waves.

    Args:
        x: X coordinate for the noise
        z: Z coordinate for the noise

    Returns:
        Noise value between -1.0 and 1.0
    """
    # Simple 2D noise using sine functions with different frequencies
    value = math.sin(x * 2) * math.sin(z * 2) * 0.5

    # Add more octave-like components for more natural appearance
    value += math.sin(x * 4) * math.sin(z * 4) * 0.25
    value += math.sin(x * 8) * math.sin(z * 8) * 0.125

    return value


def surface_height(seed: int, x: int, z: int) -> int:
    """
    Pure terrain surface height for a world column.

    Mirrors ``TerrainGenerator._simple_terrain_height`` exactly. The current
    generator derives its height purely from sine noise, so the result depends
    only on ``x`` and ``z``; ``seed`` is accepted for interface stability and
    forward compatibility.

    Args:
        seed: World seed
        x: X world coordinate
        z: Z world coordinate

    Returns:
        Height (Y coordinate) of the surface block at that column
    """
    height = BASE_HEIGHT

    # Low frequency noise for general landscape shape
    height += _noise(x * 0.01, z * 0.01) * 4

    # Medium frequency noise for hills and valleys
    height += _noise(x * 0.05, z * 0.05) * 2

    # High frequency noise for small details
    height += _noise(x * 0.1, z * 0.1) * 0.5

    return max(MIN_HEIGHT, min(MAX_HEIGHT, int(height)))


def in_lake(x: int, z: int) -> bool:
    """
    True when a world column lies inside the deterministic lake circle.

    Args:
        x: X world coordinate
        z: Z world coordinate

    Returns:
        Whether the column is part of the generated lake
    """
    return (
        (x - LAKE_CENTER_X) ** 2 + (z - LAKE_CENTER_Z) ** 2
        <= LAKE_RADIUS ** 2
    )


class TerrainGenerator:
    """
    Generates natural-looking terrain for the voxel world.
    
    This includes generating height maps, placing biomes, and creating 
    diverse terrain features like hills, valleys, caves, etc.
    """
    
    def __init__(self):
        """Initialize the terrain generator."""
        # Seed for random number generation - keep it consistent to ensure reproducible terrain
        self.seed = 42
    
    def generate_world(self, world: World) -> None:
        """
        Generate complete world terrain data.
        
        Args:
            world: World object to populate with generated terrain
        """
        # Set the seed for consistency
        random.seed(self.seed)
        
        # Generate initial terrain based on a simple height map approach
        self._generate_height_map_terrain(world)
        
    def _generate_height_map_terrain(self, world: World) -> None:
        """Generate terrain using a height map approach."""
        chunk_size = 16

        # Define a few sample chunks to generate terrain in
        for chunk_x in range(-1, 2):
            for chunk_z in range(-1, 2):
                chunk = world.get_chunk(chunk_x, 0, chunk_z)

                # For each block in chunk
                for x in range(chunk_size):
                    for z in range(chunk_size):
                        # Calculate world coordinates for this block
                        global_x = chunk_x * chunk_size + x
                        global_z = chunk_z * chunk_size + z

                        # Simple height map function that creates a relatively flat terrain with some hills
                        height = surface_height(self.seed, global_x, global_z)

                        in_lake_here = in_lake(global_x, global_z)

                        # Generate blocks based on height and position
                        for y in range(chunk_size):
                            if in_lake_here:
                                if y > LAKE_LEVEL:
                                    chunk.set_block(x, y, z, BlockType.AIR)
                                elif LAKE_FLOOR <= y <= LAKE_LEVEL:
                                    chunk.set_block(x, y, z, BlockType.WATER)
                                    chunk.set_water_level(x, y, z, 8)
                                    # Only the top lake layer holds permanent
                                    # sources; lower cells are derived water.
                                    chunk.set_water_source(
                                        x, y, z, y == LAKE_LEVEL
                                    )
                                else:
                                    if y > height:
                                        chunk.set_block(x, y, z, BlockType.AIR)
                                    elif y == height:
                                        chunk.set_block(x, y, z, BlockType.GRASS)
                                    elif y > height - 4:
                                        chunk.set_block(x, y, z, BlockType.DIRT)
                                    else:
                                        chunk.set_block(x, y, z, BlockType.STONE)
                            else:
                                if y > height:
                                    chunk.set_block(x, y, z, BlockType.AIR)
                                elif y == height:
                                    chunk.set_block(x, y, z, BlockType.GRASS)
                                elif y > height - 4:
                                    chunk.set_block(x, y, z, BlockType.DIRT)
                                else:
                                    chunk.set_block(x, y, z, BlockType.STONE)
    
    def _simple_terrain_height(self, x: int, z: int) -> int:
        """
        Calculate a simple height value for a world coordinate.

        Delegates to the module-level pure ``surface_height``.

        Args:
            x: X world coordinate
            z: Z world coordinate

        Returns:
            Height (Y-coordinate) at given position
        """
        return surface_height(self.seed, x, z)
    
    def _noise(self, x: float, z: float) -> float:
        """
        Simple noise function using sine waves.

        Delegates to the module-level pure ``_noise``.

        Args:
            x: X coordinate for the noise
            z: Z coordinate for the noise

        Returns:
            Noise value between -1.0 and 1.0
        """
        return _noise(x, z)

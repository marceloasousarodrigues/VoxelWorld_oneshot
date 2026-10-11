"""
Terrain generation module for VoxelWorld.
Generates natural-looking terrain using noise functions and height maps.
"""

import math
import random
from world import World  
from chunk import Chunk
from block_data import BlockType, is_block_solid


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
        
        lake_center_x = 0
        lake_center_z = 0
        lake_radius = 6
        lake_floor = 2
        lake_level = 4

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
                        height = self._simple_terrain_height(global_x, global_z)

                        in_lake = (
                            (global_x - lake_center_x) ** 2
                            + (global_z - lake_center_z) ** 2
                            <= lake_radius**2
                        )

                        # Generate blocks based on height and position
                        for y in range(chunk_size):
                            if in_lake:
                                if y > lake_level:
                                    chunk.set_block(x, y, z, BlockType.AIR)
                                elif lake_floor <= y <= lake_level:
                                    chunk.set_block(x, y, z, BlockType.WATER)
                                    chunk.set_water_level(x, y, z, 8)
                                    # Only the top lake layer holds permanent
                                    # sources; lower cells are derived water.
                                    chunk.set_water_source(
                                        x, y, z, y == lake_level
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
        
        Uses noise functions to create natural-looking terrain with hills and valleys.
        
        Args:
            x: X world coordinate
            z: Z world coordinate
            
        Returns:
            Height (Y-coordinate) at given position
        """
        # Set seed for reproducible results
        random.seed(self.seed + x * 1000 + z * 100)
        
        # Base height level (we'll adjust around this)
        base_height = 6
        
        # Add some variation using multiple noise functions at different frequencies
        height = base_height
        
        # Low frequency noise for general landscape shape
        height += self._noise(x * 0.01, z * 0.01) * 4
        
        # Medium frequency noise for hills and valleys  
        height += self._noise(x * 0.05, z * 0.05) * 2
        
        # High frequency noise for small details
        height += self._noise(x * 0.1, z * 0.1) * 0.5
        
        # Ensure height is within reasonable bounds (0-15)
        height = max(0, min(15, int(height)))
        
        return height
    
    def _noise(self, x: float, z: float) -> float:
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
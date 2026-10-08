"""
Unit tests for World and related classes in VoxelWorld.
"""

import unittest
from world import World
from chunk import Chunk
from terrain_generation import TerrainGenerator
from coordinate_system import get_chunk_containing_world_coords
from block_data import BlockType


class TestWorld(unittest.TestCase):
    """Test cases for the World class."""
    
    def setUp(self):
        """Set up test fixtures before each test method."""
        self.world = World()
        
    def test_create_world(self):
        """Test that a world can be created successfully."""
        self.assertIsNotNone(self.world)
        self.assertEqual(len(self.world.chunks), 0)
        
    def test_get_chunk(self):
        """Test getting chunks from the world."""
        chunk = self.world.get_chunk(0, 0, 0)
        self.assertIsInstance(chunk, Chunk)
        self.assertIn((0, 0, 0), self.world.chunks)
        
    def test_set_block(self):
        """Test setting blocks in the world."""
        # Set a block
        self.world.set_block(10, 20, 30, BlockType.GRASS)
        
        # Get it back  
        block_type = self.world.get_block(10, 20, 30)
        self.assertEqual(block_type, BlockType.GRASS)
        
    def test_get_chunk_coords_containing_world_coords(self):
        """Test coordinate conversion functions."""
        result = get_chunk_containing_world_coords(10, 20, 30)
        expected = (0, 1, 1)  # Should be in chunk (0, 1, 1) with size 16
        self.assertEqual(result, expected)
        
        # Test negative coordinates
        result = get_chunk_containing_world_coords(-10, -20, -30)
        expected = (-1, -2, -2)  # Should be in chunk (-1, -2, -2)
        self.assertEqual(result, expected)


class TestTerrainGenerator(unittest.TestCase):
    """Test cases for the TerrainGenerator class."""
    
    def test_create_generator(self):
        """Test that a terrain generator can be created.""" 
        generator = TerrainGenerator()
        self.assertIsNotNone(generator)
        
    def test_seed_consistency(self):
        """Test that noise function is deterministic with same seed."""
        generator1 = TerrainGenerator()
        generator2 = TerrainGenerator()
        
        # Both generators should produce the same values due to same seed
        height1 = generator1._simple_terrain_height(0, 0)
        height2 = generator2._simple_terrain_height(0, 0)
        
        self.assertEqual(height1, height2)


class TestChunk(unittest.TestCase):
    """Test cases for the Chunk class."""
    
    def test_create_chunk(self):
        """Test that a chunk can be created successfully."""
        chunk = Chunk(0, 0, 0)
        self.assertIsNotNone(chunk)
        self.assertEqual(chunk.chunk_x, 0)
        self.assertEqual(chunk.chunk_y, 0) 
        self.assertEqual(chunk.chunk_z, 0)
        
    def test_get_set_block(self):
        """Test setting and getting blocks in a chunk."""
        chunk = Chunk(0, 0, 0)
        
        # Default should be air
        block_type = chunk.get_block(0, 0, 0)
        self.assertEqual(block_type, BlockType.AIR)
        
        # Set a different block 
        chunk.set_block(0, 0, 0, BlockType.GRASS)
        
        # Get it back
        block_type = chunk.get_block(0, 0, 0)
        self.assertEqual(block_type, BlockType.GRASS)


if __name__ == '__main__':
    unittest.main()
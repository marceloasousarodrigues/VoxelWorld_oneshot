"""
Main entry point for VoxelWorld application.
Initializes the game window, world, and rendering system using Ursina.
"""

from ursina import *
from chunk import Chunk
from world import World
from terrain_generation import TerrainGenerator
from chunk_entity import create_chunk_entity

# Import required modules for block management
from block_data import BlockType

app = Ursina()

# Create world and terrain generator
world = World()
terrain_gen = TerrainGenerator()

print("Generating terrain...")
terrain_gen.generate_world(world)
print(f"Terrain generation complete. Chunks: {len(world.chunks)}")

chunk_entities = []
chunks_to_render = list(world.chunks.values())

print(f"Creating entities for {len(chunks_to_render)} chunks...")

for chunk in chunks_to_render:
    world_pos = (chunk.chunk_x * 16, chunk.chunk_y * 16, chunk.chunk_z * 16)
    entity = create_chunk_entity(chunk, world_pos)
    if entity:
        chunk_entities.append(entity)
        print(f"  Entity at {world_pos}: {len(entity.model.vertices)} vertices")

# Set camera for clear view of voxel terrain
# Positioned elevated to see the entire world clearly
camera.position = Vec3(60, 25, -60)
camera.look_at(Vec3(8, 3, 8))
    
print(f"Ready! Camera at {camera.position}, looking at {Vec3(8, 4, 8)}")
print("Voxel terrain should be visible in the Ursina window.")

app.run()
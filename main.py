# Main entry point for VoxelWorld with M6 Player Navigation

from ursina import Ursina

from world import World
from terrain_generation import TerrainGenerator
from chunk_entity import create_chunk_entity
from water import WaterSimulation
import player


app = Ursina()

world = World()
terrain_gen = TerrainGenerator()

print("Generating terrain...")
terrain_gen.generate_world(world)

print(
    f"Terrain complete. Chunks: {len(world.chunks)}"
)

# Water simulation. Sources are seeded once; edited chunks are re-evaluated
# through the world's external-edit log on each frame.
water_sim = WaterSimulation(world)
water_sim.seed_all_sources()


chunk_entities = []

for chunk in world.chunks.values():

    world_pos = (
        chunk.chunk_x * 16,
        chunk.chunk_y * 16,
        chunk.chunk_z * 16,
    )

    entity = create_chunk_entity(
        chunk,
        world_pos,
        world=world,
    )

    if entity:
        chunk_entities.append(entity)


print(
    f"{len(chunk_entities)} "
    f"chunk entities created successfully"
)


# Spawn above the generated terrain.
spawn_position = (8, 8, 8)

player_entity = player.VoxelPlayer(
    world=world,
    spawn_position=spawn_position,
)


print(
    f"Player spawned at {player_entity.position}"
)

print("VoxelWorld ready!")

print(
    "Use WASD to move, "
    "mouse to look around, "
    "SPACE to jump when on ground."
)


def update():
    """Rebuild dirty chunk meshes, then advance the water simulation.

    M15: interaction edits land in ``world.dirty_chunks`` and are rebuilt here
    under a per-frame budget. Water runs afterwards and is skipped when mesh
    work already consumed the frame's budget, so the player's own edit always
    wins. A water commit publishes at most the batches that fit in its own
    budget and only *marks* the affected chunks dirty, so its geometry is
    rebuilt by a later frame's ``reconcile`` rather than inside the water tick.
    """
    world.reconcile()
    water_sim.consume_changes()
    if not world.dirty_chunks:
        water_sim.tick()


app.run()
# Main entry point for VoxelWorld with M6 Player Navigation

from ursina import Ursina

from world import World
from terrain_generation import TerrainGenerator
from chunk_entity import create_chunk_entity
from chunk_streaming import ChunkStreamer
from water import WaterSimulation
import gc_tuning
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

# M16: stream chunks around the player. Chunks within the configured streaming
# distance load as the player moves; chunks beyond the retention distance unload
# and release their rendered entity. Settings live in config/world_config.json.
streamer = ChunkStreamer(
    world,
    terrain_generator=terrain_gen,
    water_sim=water_sim,
)


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

# M16 stutter fix: move the whole startup graph (world, generated chunks, their
# entities, the Panda3D graph) into the permanent generation so the cyclic
# collector's occasional full pass traces far less. Measured on the real frame
# loop: worst full-collection pause 85-113 ms -> 15-56 ms. Applied here, after
# every startup object exists and before the first frame, so nothing created
# during gameplay is ever promoted to permanent.
gc_tuning.apply()

print(
    "Use WASD to move, "
    "mouse to look around, "
    "SPACE to jump when on ground."
)


def update():
    """Rebuild dirty meshes, stream chunks around the player, then tick water.

    M15: interaction edits land in ``world.dirty_chunks`` and are rebuilt here
    under a per-frame budget, so the player's own edit always wins. The M16
    streamer runs after that rebuild and loads/unloads a bounded number of
    chunks, marking loaded neighbours for re-culling on the next frame. Water
    runs last and is skipped when mesh work already consumed the frame.
    """
    world.reconcile()
    streamer.update((player_entity.x, player_entity.y, player_entity.z))
    water_sim.consume_changes()
    if not world.dirty_chunks:
        water_sim.tick()


app.run()
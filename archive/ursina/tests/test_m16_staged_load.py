"""M16 stutter fix 3 - split one chunk load across two frames.

A cold chunk load measured 25.9 ms (16.7 ms after fix 2) plus ~14 ms of
neighbour mesh rebuilds, so every boundary crossing produced a 37-56 ms frame.
The load is now staged:

* **Stage A** registers the chunk, generates terrain + vegetation and replays the
  player-edit overlay. The chunk's logical content is complete and authoritative
  as soon as this returns, so it is collidable, raycastable and editable
  immediately; only its geometry is still empty. A single entity exists (one
  entity per loaded chunk, from this moment on), with no model yet, so no other
  caller can observe a chunk without its entity.
* **Stage B** builds the mesh into that same entity, re-culls loaded neighbours
  and bumps the water version.

The equivalence gate below is the important one: a staged load must leave the
world in exactly the state a synchronous ``World.load_chunk`` leaves it in.
"""

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from block_data import BlockType  # noqa: E402
from chunk_streaming import ChunkStreamer  # noqa: E402
from terrain_generation import TerrainGenerator  # noqa: E402
from world import World  # noqa: E402

COORD = (4, 0, 4)


def _mesh_signature(chunk):
    """The actual uploaded geometry, so staged and synchronous loads are compared
    on what is rendered rather than on a side-channel bookkeeping list."""
    entity = getattr(chunk, "entity", None)
    if entity is None:
        return None
    model = entity.model
    if model is None:
        return None
    return (
        tuple(getattr(model, "vertices", ())),
        tuple(getattr(model, "triangles", ())),
        tuple(getattr(model, "uvs", ())),
        entity.enabled,
    )


def _snapshot(world):
    """Everything a load is allowed to affect."""
    return {
        key: (
            chunk.blocks.tolist(),
            chunk.water_levels.tolist(),
            chunk.water_sources.tolist(),
            chunk.decorations.tolist(),
            chunk.entity is None,
            _mesh_signature(chunk),
        )
        for key, chunk in world.chunks.items()
    }


def test_begin_chunk_load_registers_the_data_without_geometry():
    world = World()
    generator = TerrainGenerator()

    chunk = world.begin_chunk_load(*COORD, terrain_generator=generator)

    assert world.chunks[COORD] is chunk
    assert chunk.generated is True
    assert int(chunk.blocks.max()) != 0, "terrain data must be complete at stage A"
    # One entity exists already, so no caller can see a chunk without its entity.
    assert chunk.entity is not None
    # ... but it carries no geometry yet.
    assert chunk.entity.model is None
    assert chunk.entity.enabled is False


def test_finish_chunk_load_fills_the_same_entity():
    world = World()
    generator = TerrainGenerator()

    chunk = world.begin_chunk_load(*COORD, terrain_generator=generator)
    entity = chunk.entity

    world.finish_chunk_load(chunk)

    assert world.chunks[COORD] is chunk
    assert chunk.entity is entity, "stage B must reuse the stage-A entity"
    assert chunk.entity.model is not None
    assert chunk.entity.enabled is True
    assert len(world.chunks) == 1


def test_staged_load_matches_a_synchronous_load():
    """The equivalence gate: staged and synchronous loads are indistinguishable."""
    generator = TerrainGenerator()

    synchronous = World()
    synchronous.load_chunk(*COORD, terrain_generator=generator)

    staged = World()
    chunk = staged.begin_chunk_load(*COORD, terrain_generator=generator)
    staged.finish_chunk_load(chunk)

    assert _snapshot(staged) == _snapshot(synchronous)
    assert staged.dirty_chunks == synchronous.dirty_chunks
    assert staged.water_edit_version == synchronous.water_edit_version
    assert set(staged.chunks) == set(synchronous.chunks)


def test_staged_load_reproduces_the_surrounding_neighbour_dirtying():
    """A load into a populated neighbourhood re-culls exactly as before."""
    generator = TerrainGenerator()

    def populate_and_load():
        world = World()
        for chunk_x in (3, 5):
            world.load_chunk(chunk_x, 0, 4, terrain_generator=generator)
        world.dirty_chunks.clear()
        return world

    synchronous = populate_and_load()
    synchronous.load_chunk(*COORD, terrain_generator=generator)

    staged = populate_and_load()
    staged.finish_chunk_load(staged.begin_chunk_load(*COORD, terrain_generator=generator))

    assert staged.dirty_chunks == synchronous.dirty_chunks
    assert _snapshot(staged) == _snapshot(synchronous)


def test_player_edits_survive_a_staged_load():
    world = World()
    generator = TerrainGenerator()
    # An edit in the target chunk, applied while it is not loaded.
    world.set_block(COORD[0] * 16 + 2, 12, COORD[2] * 16 + 3, BlockType.STONE)

    chunk = world.begin_chunk_load(*COORD, terrain_generator=generator)
    world.finish_chunk_load(chunk)

    assert chunk.get_block(2, 12, 3) == BlockType.STONE


def test_streamer_stages_a_load_across_two_updates():
    world = World()
    streamer = ChunkStreamer(
        world,
        terrain_generator=TerrainGenerator(),
        streaming_distance=1,
        retention_distance=1,
        max_loads_per_frame=1,
        max_unloads_per_frame=1,
    )

    first = streamer.update((8, 8, 8))

    assert first["loaded"] == 1
    assert len(world.chunks) == 1
    key = (0, 0, 0)
    staged = world.chunks[key]
    assert staged.entity is not None
    assert staged.entity.model is None, "stage A must not have built geometry yet"
    # The registry still reports one entity per registered chunk, exactly.
    assert set(streamer.rendered) == set(world.chunks)
    assert streamer.rendered[key] is staged.entity
    # ... and the streamer knows it still owes work.
    assert streamer.has_pending_work() is True

    second = streamer.update((8, 8, 8))

    assert second["loaded"] == 0, "the second update finishes, it does not start"
    assert staged.entity.model is not None, "stage B must have built the geometry"
    assert streamer.rendered[key] is staged.entity
    assert len(world.chunks) == 1


def test_staged_streaming_converges_with_one_entity_per_chunk():
    world = World()
    streamer = ChunkStreamer(
        world,
        terrain_generator=TerrainGenerator(),
        streaming_distance=2,
        retention_distance=2,
        max_loads_per_frame=2,
        max_unloads_per_frame=2,
    )
    position = (40, 8, 40)
    desired = streamer.desired_chunk_keys(position)

    for _ in range(500):
        streamer.update(position)
        if not streamer.has_pending_work():
            break
    else:
        raise AssertionError("staged streaming did not converge")

    assert set(world.chunks) == desired
    assert set(streamer.rendered) == set(world.chunks)
    for key, entity in streamer.rendered.items():
        assert world.chunks[key].entity is entity
        assert entity is not None
        assert entity.model is not None, "every converged chunk must be meshed"


def test_unloading_a_chunk_that_is_still_staged_is_safe():
    world = World()
    streamer = ChunkStreamer(
        world,
        terrain_generator=TerrainGenerator(),
        streaming_distance=1,
        retention_distance=1,
        max_loads_per_frame=1,
        max_unloads_per_frame=4,
    )

    streamer.update((8, 8, 8))
    assert (0, 0, 0) in world.chunks
    assert world.chunks[(0, 0, 0)].entity.model is None

    # Jump far away: the staged chunk is now far outside the retention radius.
    for _ in range(40):
        streamer.update((400, 8, 400))
        if not streamer.has_pending_work():
            break

    assert (0, 0, 0) not in world.chunks
    assert (0, 0, 0) not in streamer.rendered
    # The far position still resolved to a meshed chunk.
    for key, entity in streamer.rendered.items():
        assert world.chunks[key].entity is entity
        assert entity.model is not None


def test_dirty_tracking_is_not_triggered_by_stage_a():
    """Stage A adds data, not geometry: the chunk itself is not dirty."""
    world = World()
    generator = TerrainGenerator()
    world.begin_chunk_load(*COORD, terrain_generator=generator)
    assert COORD not in world.dirty_chunks


if __name__ == "__main__":
    test_begin_chunk_load_registers_the_data_without_geometry()
    test_finish_chunk_load_fills_the_same_entity()
    test_staged_load_matches_a_synchronous_load()
    test_staged_load_reproduces_the_surrounding_neighbour_dirtying()
    test_player_edits_survive_a_staged_load()
    test_streamer_stages_a_load_across_two_updates()
    test_staged_streaming_converges_with_one_entity_per_chunk()
    test_unloading_a_chunk_that_is_still_staged_is_safe()
    test_dirty_tracking_is_not_triggered_by_stage_a()
    print("M16 staged load tests passed!")

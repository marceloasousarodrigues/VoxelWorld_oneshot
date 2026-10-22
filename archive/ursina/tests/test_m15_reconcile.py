"""M15 Tasks 4 & 5 - deferred, batched, budgeted mesh reconciliation.

These tests pin the new contract:

* block data changes immediately and is observable before any mesh rebuild;
* the player interaction path no longer rebuilds meshes inline;
* one reconcile rebuilds at most one chunk per affected chunk;
* a per-frame budget bounds the work, and the queue drains over frames;
* the most recently edited chunk is rebuilt first;
* no unbounded accumulation is possible.
"""

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from block_data import BlockType  # noqa: E402
from player import VoxelPlayer  # noqa: E402
from world import World  # noqa: E402


def _world_with_blocks(blocks, budget_ms=None):
    world = World(mesh_budget_ms=budget_ms)
    for (x, y, z), block_type in blocks:
        world.set_block(x, y, z, block_type)
    world.refresh()
    world.dirty_chunks.clear()
    return world


def _player(world, direction=(1, 0, 0), origin=(0.5, 0.5, 0.5)):
    player = VoxelPlayer(world, spawn_position=(8, 10, 8))
    player.interaction_range = 6.0
    player.get_interaction_ray = lambda: (origin, direction)
    return player


def test_player_break_defers_inline_rebuild():
    world = _world_with_blocks([((2, 0, 0), BlockType.DIRT)])
    chunk = world.chunks[(0, 0, 0)]
    before = list(chunk._mesh_vertices)
    assert before

    player = _player(world)
    assert player.break_block() == (2, 0, 0)

    # Data changed immediately, the chunk is queued, and nothing was rebuilt.
    assert world.get_block(2, 0, 0) == BlockType.AIR
    assert (0, 0, 0) in world.dirty_chunks
    assert world.rebuild_count == 0
    assert chunk._mesh_vertices == before

    world.reconcile()
    assert world.dirty_chunks == set()
    assert world.rebuild_count == 1
    # The removed block's geometry is gone.
    assert len(chunk._mesh_vertices) < len(before)


def test_player_place_defers_inline_rebuild():
    world = _world_with_blocks([((2, 0, 0), BlockType.DIRT)])
    player = _player(world)
    player.inventory.add_item(BlockType.STONE, 8)

    assert player.place_block() == (1, 0, 0)
    assert world.get_block(1, 0, 0) == BlockType.STONE
    assert (0, 0, 0) in world.dirty_chunks
    assert world.rebuild_count == 0

    world.reconcile()
    assert world.dirty_chunks == set()
    assert world.rebuild_count == 1


def test_raycast_and_reads_see_the_edit_before_any_reconcile():
    world = _world_with_blocks([((2, 0, 0), BlockType.DIRT)])
    player = _player(world)
    player.break_block()

    # No reconcile has run, yet reads already observe the new state.
    assert world.get_block(2, 0, 0) == BlockType.AIR
    from raycast import raycast

    # The only solid block was the one just broken, so the ray now hits nothing.
    hit = raycast((0.5, 0.5, 0.5), (1, 0, 0), world, 6.0)
    assert hit is None


def test_many_edits_in_one_chunk_produce_one_rebuild():
    world = _world_with_blocks(
        [((x, 0, 0), BlockType.DIRT) for x in (1, 2, 3, 4, 5)],
        budget_ms=10_000.0,
    )
    world.refresh()
    world.dirty_chunks.clear()
    world.rebuild_count = 0

    for x in (1, 2, 3, 4, 5):
        world.set_block(x, 0, 0, BlockType.STONE)

    rebuilt = world.reconcile()
    assert rebuilt == 1
    assert world.dirty_chunks == set()


def test_edits_in_different_chunks_produce_one_rebuild_each():
    world = World(mesh_budget_ms=10_000.0)
    world.get_chunk(0, 0, 0)
    world.get_chunk(1, 0, 0)
    world.refresh()
    world.dirty_chunks.clear()
    world.rebuild_count = 0

    world.set_block(1, 1, 1, BlockType.STONE)
    world.set_block(17, 1, 1, BlockType.STONE)

    rebuilt = world.reconcile()
    assert rebuilt == 2
    assert world.dirty_chunks == set()


def test_boundary_edit_dirties_and_rebuilds_the_neighbour():
    world = World(mesh_budget_ms=10_000.0)
    world.get_chunk(0, 0, 0)
    world.get_chunk(1, 0, 0)
    world.refresh()
    world.dirty_chunks.clear()

    world.set_block(15, 1, 1, BlockType.STONE)

    assert (0, 0, 0) in world.dirty_chunks
    assert (1, 0, 0) in world.dirty_chunks

    world.reconcile()
    assert world.dirty_chunks == set()
    # Both chunks were rebuilt exactly once.
    assert world.rebuild_count == 2


def test_repeated_edit_reconcile_leaves_no_accumulation():
    world = _world_with_blocks([((2, 0, 0), BlockType.DIRT)], budget_ms=10_000.0)
    player = _player(world)
    player.inventory.add_item(BlockType.STONE, 64)

    for _ in range(20):
        world.set_block(2, 0, 0, BlockType.AIR)
        world.set_block(2, 0, 0, BlockType.STONE)
        world.reconcile()

    assert world.dirty_chunks == set()


def test_budget_rebuilds_at_most_one_chunk_per_step():
    world = World(mesh_budget_ms=0.0)
    for chunk_x in range(3):
        chunk = world.get_chunk(chunk_x, 0, 0)
        chunk.set_block(1, 1, 1, BlockType.STONE)
    world.refresh()
    world.dirty_chunks.clear()
    world.rebuild_count = 0

    world.dirty_chunks.update({(0, 0, 0), (1, 0, 0), (2, 0, 0)})
    first = world.reconcile()
    assert first == 1
    assert len(world.dirty_chunks) == 2

    second = world.reconcile()
    assert second == 1
    assert len(world.dirty_chunks) == 1

    third = world.reconcile()
    assert third == 1
    assert world.dirty_chunks == set()


def test_edited_chunk_is_rebuilt_first():
    world = World(mesh_budget_ms=0.0)
    for chunk_x in range(3):
        world.get_chunk(chunk_x, 0, 0)
    world.refresh()
    world.dirty_chunks.clear()
    world.rebuild_count = 0

    # Edit chunk (2, 0, 0): it must be the one rebuilt on the next step.
    world.set_block(2 * 16 + 1, 1, 1, BlockType.STONE)
    assert world.recent_edit_chunk == (2, 0, 0)
    world.dirty_chunks.update({(0, 0, 0), (1, 0, 0), (2, 0, 0)})

    world.reconcile()
    assert world.rebuild_count == 1
    assert (2, 0, 0) not in world.dirty_chunks
    assert (0, 0, 0) in world.dirty_chunks


def test_large_dirty_set_drains_across_frames_without_loss():
    world = World(mesh_budget_ms=0.0)
    keys = []
    for chunk_x in range(3):
        for chunk_z in range(3):
            world.get_chunk(chunk_x, 0, chunk_z)
            keys.append((chunk_x, 0, chunk_z))
    world.refresh()
    world.dirty_chunks.clear()
    world.rebuild_count = 0

    world.dirty_chunks.update(keys)
    steps = 0
    while world.dirty_chunks and steps < 100:
        world.reconcile()
        steps += 1

    assert world.dirty_chunks == set()
    # Each dirty chunk was rebuilt exactly once: no work lost or duplicated.
    assert world.rebuild_count == len(keys)


if __name__ == "__main__":
    test_player_break_defers_inline_rebuild()
    test_player_place_defers_inline_rebuild()
    test_raycast_and_reads_see_the_edit_before_any_reconcile()
    test_many_edits_in_one_chunk_produce_one_rebuild()
    test_edits_in_different_chunks_produce_one_rebuild_each()
    test_boundary_edit_dirties_and_rebuilds_the_neighbour()
    test_repeated_edit_reconcile_leaves_no_accumulation()
    test_budget_rebuilds_at_most_one_chunk_per_step()
    test_edited_chunk_is_rebuilt_first()
    test_large_dirty_set_drains_across_frames_without_loss()
    print("M15 reconcile tests passed!")

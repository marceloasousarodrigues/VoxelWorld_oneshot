"""M16 stutter fix 4 - reuse the highlight entities instead of rebuilding them.

``BlockHighlight.create_highlight`` used to destroy and re-create 13 cube
entities on every transition between "something is targeted" and "nothing is
targeted" (measured 2.203 ms median, p95 3.573 ms per event; a camera swinging
across a boundary produces ~11 such events per 240 frames). Repositioning the
existing child entities is measured at 0.009 ms.

These tests pin the contract the old implementation had - ``highlight_entity`` is
``None`` when nothing is targeted, a live entity at the block centre when
something is, and ``visible`` is True on a hit - plus the no-accumulation
behaviour that is the whole point of the change.
"""

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from block_data import BlockType  # noqa: E402
from highlight import BlockHighlight  # noqa: E402
from player import VoxelPlayer  # noqa: E402
from world import World  # noqa: E402

# A cube box outline: 4 bottom, 4 top, 4 vertical edge children under one
# parent entity (13 Entity objects created per event in the old implementation).
EXPECTED_EDGE_CHILDREN = 12


def _child_count(highlight) -> int:
    entity = highlight.highlight_entity
    if entity is None:
        return 0
    return len(entity.children)


def test_highlight_entity_is_none_before_anything_is_targeted():
    highlight = BlockHighlight()
    assert highlight.highlight_entity is None
    assert _child_count(highlight) == 0


def test_create_highlight_positions_at_the_block_centre_with_edge_children():
    highlight = BlockHighlight()
    highlight.create_highlight((2, 0, 0))
    assert highlight.highlight_entity is not None
    assert highlight.highlight_entity.position == (2.5, 0.5, 0.5)
    assert highlight.highlight_entity.visible is True
    assert _child_count(highlight) == EXPECTED_EDGE_CHILDREN


def test_repeated_create_highlight_does_not_accumulate_entities():
    """The regression: rebuild-every-event used to churn 13 entities per event."""
    highlight = BlockHighlight()
    for index in range(12):
        highlight.create_highlight((index % 16, 8, (index * 3) % 16))
        assert _child_count(highlight) == EXPECTED_EDGE_CHILDREN


def test_create_update_remove_cycles_never_exceed_13_children():
    highlight = BlockHighlight()
    for index in range(12):
        highlight.create_highlight((index % 16, 4, index % 16))
        highlight.update_highlight((index % 16, 5, index % 16))
        assert highlight.highlight_entity.position == (index % 16 + 0.5, 5.5, index % 16 + 0.5)
        assert _child_count(highlight) == EXPECTED_EDGE_CHILDREN
        highlight.remove_highlight()
        assert highlight.highlight_entity is None


def test_update_highlight_moves_without_adding_entities():
    highlight = BlockHighlight()
    highlight.create_highlight((0, 0, 0))
    children = list(highlight.highlight_entity.children)
    highlight.update_highlight((7, 3, 9))
    assert highlight.highlight_entity.position == (7.5, 3.5, 9.5)
    assert list(highlight.highlight_entity.children) == children
    assert len(children) == EXPECTED_EDGE_CHILDREN


def test_remove_highlight_hides_and_create_highlight_reshows():
    highlight = BlockHighlight()
    highlight.create_highlight((1, 1, 1))
    highlight.remove_highlight()
    assert highlight.highlight_entity is None
    highlight.create_highlight((5, 1, 1))
    assert highlight.highlight_entity.visible is True
    assert highlight.highlight_entity.position == (5.5, 1.5, 1.5)
    assert _child_count(highlight) == EXPECTED_EDGE_CHILDREN


def test_update_before_create_is_harmless():
    highlight = BlockHighlight()
    highlight.update_highlight((3, 3, 3))  # no-op, must not raise
    assert highlight.highlight_entity is None


def test_remove_before_create_is_harmless():
    highlight = BlockHighlight()
    highlight.remove_highlight()
    assert highlight.highlight_entity is None


def test_player_interaction_still_drives_the_highlight():
    """The sprite the player sees still appears on a hit and clears on a miss."""

    def make_player(blocks):
        world = World()
        for (x, y, z), block in blocks:
            world.set_block(x, y, z, block)
        player = VoxelPlayer(world)
        player.get_interaction_ray = lambda: ((0.5, 0.5, 0.5), (1, 0, 0))
        return player

    player = make_player([((2, 0, 0), BlockType.DIRT)])
    player._update_interaction()
    assert player.highlight.highlight_entity is not None
    assert player.highlight.highlight_entity.position == (2.5, 0.5, 0.5)
    # Re-running the interaction must be idempotent, not re-creating the edges.
    for _ in range(5):
        player._update_interaction()
    assert len(player.highlight.highlight_entity.children) == EXPECTED_EDGE_CHILDREN

    player = make_player([])
    player._update_interaction()
    assert player.highlight.highlight_entity is None


if __name__ == "__main__":
    test_highlight_entity_is_none_before_anything_is_targeted()
    test_create_highlight_positions_at_the_block_centre_with_edge_children()
    test_repeated_create_highlight_does_not_accumulate_entities()
    test_create_update_remove_cycles_never_exceed_13_children()
    test_update_highlight_moves_without_adding_entities()
    test_remove_highlight_hides_and_create_highlight_reshows()
    test_update_before_create_is_harmless()
    test_remove_before_create_is_harmless()
    test_player_interaction_still_drives_the_highlight()
    print("M16 highlight reuse tests passed!")

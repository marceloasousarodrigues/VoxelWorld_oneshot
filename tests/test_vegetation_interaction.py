import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from world import World
from block_data import BlockType


def test_placing_block_clears_decoration_in_cell():
    w = World()
    c = w.get_chunk(0, 0, 0)
    c.set_block(1, 1, 1, BlockType.GRASS)
    c.set_decoration(1, 2, 1, 3)
    w.set_block(1, 2, 1, BlockType.STONE)
    assert c.get_decoration(1, 2, 1) == 0


def test_removing_support_clears_decoration_above():
    w = World()
    c = w.get_chunk(0, 0, 0)
    c.set_block(1, 1, 1, BlockType.GRASS)
    c.set_decoration(1, 2, 1, 3)
    w.set_block(1, 1, 1, BlockType.AIR)
    assert c.get_decoration(1, 2, 1) == 0


def test_set_block_still_marks_dirty_and_records_edit():
    w = World()
    w.get_chunk(0, 0, 0)
    w.set_block(1, 1, 1, BlockType.STONE)
    assert (0, 0, 0) in w.dirty_chunks
    assert (1, 1, 1) in w.changed_blocks

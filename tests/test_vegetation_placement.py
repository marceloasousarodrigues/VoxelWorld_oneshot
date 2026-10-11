import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from chunk import Chunk


def test_decoration_defaults_and_roundtrip():
    c = Chunk(0, 0, 0)
    assert c.get_decoration(1, 2, 3) == 0

    c.set_decoration(1, 2, 3, 4)

    assert c.get_decoration(1, 2, 3) == 4


def test_clear_decoration_resets_to_none():
    c = Chunk(0, 0, 0)
    c.set_decoration(0, 0, 0, 2)

    c.clear_decoration(0, 0, 0)

    assert c.get_decoration(0, 0, 0) == 0


def test_decoration_layer_does_not_touch_blocks():
    c = Chunk(0, 0, 0)

    c.set_decoration(5, 5, 5, 3)

    assert c.get_block(5, 5, 5) == 0  # AIR unchanged

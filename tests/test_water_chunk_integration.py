import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from chunk import Chunk


def test_chunk_water_layer_defaults_and_roundtrip():
    c = Chunk(0, 0, 0)
    assert c.get_water_level(1, 2, 3) == 0
    assert c.get_water_source(1, 2, 3) is False

    c.set_water_level(1, 2, 3, 5)
    c.set_water_source(1, 2, 3, True)

    assert c.get_water_level(1, 2, 3) == 5
    assert c.get_water_source(1, 2, 3) is True


def test_chunk_water_level_clamped_and_clear_water():
    c = Chunk(0, 0, 0)

    c.set_water_level(0, 0, 0, 99)
    assert c.get_water_level(0, 0, 0) == 8

    c.set_water_level(0, 0, 0, -3)
    assert c.get_water_level(0, 0, 0) == 0

    c.set_water_level(0, 0, 0, 4)
    c.set_water_source(0, 0, 0, True)
    c.clear_water(0, 0, 0)

    assert c.get_water_level(0, 0, 0) == 0
    assert c.get_water_source(0, 0, 0) is False


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
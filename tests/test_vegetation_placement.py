import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from chunk import Chunk
from terrain_generation import surface_height, in_lake, LAKE_LEVEL
import vegetation


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


def _fresh_chunk(cx=0, cz=0, seed=42):
    c = Chunk(cx, 0, cz)
    # minimal terrain: fill the grass surface via the same pure function
    for x in range(16):
        for z in range(16):
            gx, gz = cx * 16 + x, cz * 16 + z
            h = surface_height(seed, gx, gz)
            for y in range(h + 1):
                c.set_block(x, y, z, 1 if y == h else 2)  # GRASS / DIRT
    return c


def test_tufts_only_on_exposed_grass():
    c = _fresh_chunk()
    vegetation.generate_vegetation_for_chunk(c, 42)
    for x in range(16):
        for z in range(16):
            gx, gz = x, z
            if in_lake(gx, gz):
                continue
            y = surface_height(42, gx, gz) + 1
            if y > 15:
                continue
            v = c.get_decoration(x, y, z)
            if v:
                assert c.get_block(x, y - 1, z) == 1  # GRASS support
                assert c.get_block(x, y, z) == 0     # AIR above


def test_no_tufts_above_y15_or_in_lake():
    c = _fresh_chunk()
    vegetation.generate_vegetation_for_chunk(c, 42)
    for x in range(16):
        for y in range(16):
            for z in range(16):
                if c.get_decoration(x, y, z):
                    assert y <= 15
                    assert not in_lake(x, z)


def test_tuft_density_is_reasonable():
    placed = total = 0
    for cx in range(-2, 3):
        c = _fresh_chunk(cx, 0)
        vegetation.generate_vegetation_for_chunk(c, 42)
        for x in range(16):
            for z in range(16):
                gx = cx * 16 + x
                y = surface_height(42, gx, z) + 1
                if in_lake(gx, z) or y > 15:
                    continue
                total += 1
                if c.get_decoration(x, y, z):
                    placed += 1
    assert total > 0
    assert 0.15 < placed / total < 0.5

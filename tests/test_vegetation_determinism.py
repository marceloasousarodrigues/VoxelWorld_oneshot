import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from terrain_generation import surface_height, in_lake, LAKE_RADIUS
import vegetation


def test_surface_height_matches_generator():
    from terrain_generation import TerrainGenerator

    gen = TerrainGenerator()
    for (x, z) in [(0, 0), (5, -3), (-17, 22), (100, -100)]:
        assert surface_height(gen.seed, x, z) == gen._simple_terrain_height(x, z)


def test_hash32_is_stable_and_bounded():
    a = vegetation.hash32(42, 3, -7, 1)
    b = vegetation.hash32(42, 3, -7, 1)
    assert a == b
    assert 0 <= a < 2**32
    assert vegetation.hash32(42, 3, -7, 2) != vegetation.hash32(42, 3, -7, 1)


def test_in_lake_matches_radius():
    assert in_lake(0, 0) is True
    assert in_lake(LAKE_RADIUS + 5, 0) is False

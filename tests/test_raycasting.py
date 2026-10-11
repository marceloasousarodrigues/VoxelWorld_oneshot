import sys
sys.path.append('.')

from raycast import raycast
from world import World
from block_data import BlockType

# Test constants
DIRT = BlockType.DIRT
STONE = BlockType.STONE
WATER = BlockType.WATER
AIR = 0


def make_world(blocks):
    """Build a World containing the given ((x, y, z), block_type) pairs."""
    world = World()
    for (x, y, z), block_type in blocks:
        world.set_block(x, y, z, block_type)
    return world


def test_ray_cast_solid_block():
    world = make_world([((0, 0, 0), DIRT)])

    # Cast ray from origin toward block
    origin = (0.5, 0.5, 0.5)
    direction = (1, 0, 0)

    hit = raycast(origin, direction, world)
    assert hit is not None
    assert hit['position'] == (0, 0, 0)


def test_raycast_hits_first_solid_block_along_axis():
    # A dirt block before a stone block: the dirt must be reported.
    world = make_world([((1, 0, 0), DIRT), ((3, 0, 0), STONE)])

    hit = raycast((0.5, 0.5, 0.5), (1, 0, 0), world)
    assert hit is not None
    assert hit['position'] == (1, 0, 0)
    assert hit['block_type'] == DIRT


def test_raycast_negative_axis_direction():
    world = make_world([((-2, 0, 0), DIRT)])

    hit = raycast((0.5, 0.5, 0.5), (-1, 0, 0), world)
    assert hit is not None
    assert hit['position'] == (-2, 0, 0)


def test_raycast_vertical_direction():
    world = make_world([((0, 2, 0), DIRT)])

    hit = raycast((0.5, 0.5, 0.5), (0, 1, 0), world)
    assert hit is not None
    assert hit['position'] == (0, 2, 0)
    assert hit['face'] == (0, -1, 0)
    assert hit['neighbor_pos'] == (0, 1, 0)


def test_raycast_face_and_neighbor_position():
    world = make_world([((2, 0, 0), DIRT)])

    hit = raycast((0.5, 0.5, 0.5), (1, 0, 0), world)
    assert hit is not None
    assert hit['face'] == (-1, 0, 0)
    assert hit['neighbor_pos'] == (1, 0, 0)
    # neighbor_pos is always position + face.
    assert hit['neighbor_pos'] == tuple(
        p + f for p, f in zip(hit['position'], hit['face'])
    )


def test_raycast_respects_max_range():
    # Distance from x=0.5 to the x=6 cell is 5.5 (in range) and to the
    # x=7 cell is 6.5 (out of the default 6-block range).
    in_range = make_world([((6, 0, 0), DIRT)])
    out_of_range = make_world([((7, 0, 0), DIRT)])

    hit = raycast((0.5, 0.5, 0.5), (1, 0, 0), in_range)
    assert hit is not None
    assert hit['position'] == (6, 0, 0)

    assert raycast((0.5, 0.5, 0.5), (1, 0, 0), out_of_range) is None


def test_raycast_returns_correct_block_type():
    world = make_world([((1, 0, 0), STONE)])

    hit = raycast((0.5, 0.5, 0.5), (1, 0, 0), world)
    assert hit is not None
    assert hit['block_type'] == STONE


def test_raycast_diagonal_ray():
    world = make_world([((2, 2, 0), DIRT)])

    hit = raycast((0.5, 0.5, 0.5), (1, 1, 0), world)
    assert hit is not None
    assert hit['position'] == (2, 2, 0)


def test_raycast_diagonal_ray_3d():
    world = make_world([((1, 1, 1), DIRT)])

    hit = raycast((0.5, 0.5, 0.5), (1, 1, 1), world)
    assert hit is not None
    assert hit['position'] == (1, 1, 1)


def test_raycast_crosses_chunk_boundary_positive():
    # x=16 lives in chunk 1, x=15 in chunk 0.
    world = make_world([((16, 0, 0), DIRT)])

    hit = raycast((15.5, 0.5, 0.5), (1, 0, 0), world)
    assert hit is not None
    assert hit['position'] == (16, 0, 0)
    assert hit['face'] == (-1, 0, 0)
    assert hit['neighbor_pos'] == (15, 0, 0)


def test_raycast_crosses_chunk_boundary_negative():
    # x=-1 lives in chunk -1, x=0 in chunk 0.
    world = make_world([((0, 0, 0), DIRT)])

    hit = raycast((-0.5, 0.5, 0.5), (1, 0, 0), world)
    assert hit is not None
    assert hit['position'] == (0, 0, 0)
    assert hit['face'] == (-1, 0, 0)
    assert hit['neighbor_pos'] == (-1, 0, 0)


def test_raycast_no_hit_in_empty_world():
    world = make_world([])

    assert raycast((0.5, 0.5, 0.5), (1, 0, 0), world) is None
    assert raycast((0.5, 0.5, 0.5), (0, 1, 0), world) is None
    assert raycast((0.5, 0.5, 0.5), (0, 0, 1), world) is None


def test_raycast_passes_through_non_solid_blocks():
    # Water is not solid, so the ray must report the dirt behind it.
    world = make_world([((1, 0, 0), WATER), ((2, 0, 0), DIRT)])

    hit = raycast((0.5, 0.5, 0.5), (1, 0, 0), world)
    assert hit is not None
    assert hit['position'] == (2, 0, 0)
    assert hit['block_type'] == DIRT


def test_raycast_accepts_unnormalized_direction():
    world = make_world([((2, 0, 0), DIRT)])

    hit = raycast((0.5, 0.5, 0.5), (10, 0, 0), world)
    assert hit is not None
    assert hit['position'] == (2, 0, 0)


def test_raycast_zero_direction_returns_none():
    world = make_world([((1, 0, 0), DIRT)])

    assert raycast((0.5, 0.5, 0.5), (0, 0, 0), world) is None


if __name__ == "__main__":
    test_ray_cast_solid_block()
    test_raycast_hits_first_solid_block_along_axis()
    test_raycast_negative_axis_direction()
    test_raycast_vertical_direction()
    test_raycast_face_and_neighbor_position()
    test_raycast_respects_max_range()
    test_raycast_returns_correct_block_type()
    test_raycast_diagonal_ray()
    test_raycast_diagonal_ray_3d()
    test_raycast_crosses_chunk_boundary_positive()
    test_raycast_crosses_chunk_boundary_negative()
    test_raycast_no_hit_in_empty_world()
    test_raycast_passes_through_non_solid_blocks()
    test_raycast_accepts_unnormalized_direction()
    test_raycast_zero_direction_returns_none()
    print("All raycast tests passed!")

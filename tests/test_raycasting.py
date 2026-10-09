import sys
sys.path.append('.')

from world import World
from block_data import BlockType

DIRT = BlockType.DIRT

def test_ray_cast_exists():
    # This just verifies that raycasting module can be imported and basic function exists
    from raycast import raycast
    assert callable(raycast)
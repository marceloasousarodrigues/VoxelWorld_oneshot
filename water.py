"""
Deterministic water solver for VoxelWorld.

Implements source-derived 0-1 BFS water simulation with:
- Vertical priority (downward flow takes precedence)
- Bounded horizontal spread (max 7 blocks from source)
- Source-derived levels (cost = horizontal distance from source)
- Deterministic 0-1 BFS for level computation
"""

from collections import deque
from typing import Dict, Tuple, Set, Any

from block_data import BlockType

MAX_LEVEL = 8
SOURCE_LEVEL = 8
MAX_HORIZONTAL_SPREAD = 7

DEFAULT_MAX_CELLS_PER_TICK = 65536


def is_water(block_type: int) -> bool:
    """Check if a block type is water."""
    return block_type == BlockType.WATER


def is_passable(block_type: int) -> bool:
    """Check if a block type is passable (AIR or WATER)."""
    return block_type in (BlockType.AIR, BlockType.WATER)


def is_empty(block_type: int) -> bool:
    """Check if a block type is empty (AIR only)."""
    return block_type == BlockType.AIR


# Six orthogonal directions: +x, -x, +y, -y, +z, -z
NEIGHBORS = [
    (1, 0, 0),   # +x
    (-1, 0, 0),  # -x
    (0, 1, 0),   # +y (up)
    (0, -1, 0),  # -y (down)
    (0, 0, 1),   # +z
    (0, 0, -1),  # -z
]


def _flood_region(view: Any, seeds: list[Tuple[int, int, int]]) -> Tuple[Set[Tuple[int, int, int]], Set[Tuple[int, int, int]]]:
    """
    Flood-fill to find the connected WATER component from seeds and
    all reachable passable cells (AIR or WATER).
    
    Returns:
        region: set of water cells (by block type) in the connected component
        reachable: all passable cells (AIR or WATER) reachable from the region
    """
    region = set()
    reachable = set()
    queue = deque()
    
    for seed in seeds:
        if isinstance(seed, tuple) and len(seed) == 3:
            queue.append(seed)
    
    while queue:
        x, y, z = queue.popleft()
        
        if (x, y, z) in region:
            continue
        
        # Only process loaded chunks
        if not view.is_loaded(x, y, z):
            continue
        
        block = view.get_block(x, y, z)
        if block != BlockType.WATER:
            continue
        
        region.add((x, y, z))
        reachable.add((x, y, z))
        
        # Add all 6-connected water neighbors to queue
        for dx, dy, dz in NEIGHBORS:
            nx, ny, nz = x + dx, y + dy, z + dz
            if (nx, ny, nz) not in region:
                # Check if neighbor is water
                if view.is_loaded(nx, ny, nz):
                    nblock = view.get_block(nx, ny, nz)
                    if nblock == BlockType.WATER:
                        queue.append((nx, ny, nz))
        
        # Also add passable neighbors (AIR or WATER) to reachable
        for dx, dy, dz in NEIGHBORS:
            nx, ny, nz = x + dx, y + dy, z + dz
            if (nx, ny, nz) in reachable:
                continue
            if view.is_loaded(nx, ny, nz):
                nblock = view.get_block(nx, ny, nz)
                if nblock in (BlockType.AIR, BlockType.WATER):
                    reachable.add((nx, ny, nz))
    
    return region, reachable


def solve_water_view(view: Any, seeds: list[Tuple[int, int, int]], max_horizontal_spread: int = MAX_HORIZONTAL_SPREAD) -> Dict[Tuple[int, int, int], int]:
    """
    Solve water levels for a region using source-derived 0-1 BFS.
    
    Returns a dict mapping cell coordinates to their water level (1-8).
    Cells not in the result should drain to AIR.
    """
    # Flood to find the affected region
    region, reachable = _flood_region(view, seeds)
    
    if not region:
        return {}
    
    # Find sources in the region
    sources = {cell for cell in region if view.is_source(*cell)}
    
    if not sources:
        return {}  # No sources = everything drains
    
    # 0-1 BFS from all sources
    # Cost: vertical (down) = 0, horizontal = 1
    # We use a deque for 0-1 BFS: cost 0 pushes to front, cost 1 to back
    dist: Dict[Tuple[int, int, int], int] = {}
    queue = deque()
    
    # Initialize sources with distance 0
    for sx, sy, sz in sources:
        dist[(sx, sy, sz)] = 0
        queue.appendleft((sx, sy, sz))
    
    while queue:
        x, y, z = queue.popleft()
        current_cost = dist[(x, y, z)]
        
        if current_cost >= MAX_HORIZONTAL_SPREAD:
            continue
        
        # Check cell below (vertical, cost 0)
        if view.is_loaded(x, y - 1, z):
            below_block = view.get_block(x, y - 1, z)
            if below_block in (BlockType.AIR, BlockType.WATER):
                # Vertical step: cost 0 (downward flow priority)
                new_cost = current_cost
                cell = (x, y - 1, z)
                if cell not in dist or new_cost < dist[cell]:
                    dist[cell] = new_cost
                    queue.appendleft(cell)
        
        # Horizontal neighbors (cost 1)
        # Only if cell below is NOT empty AIR (i.e., not falling)
        below_solid = False
        if view.is_loaded(x, y - 1, z):
            below_block = view.get_block(x, y - 1, z)
            if below_block not in (BlockType.AIR, BlockType.WATER):
                below_solid = True
        
        if below_solid:
            for dx, dy, dz in [(1, 0, 0), (-1, 0, 0), (0, 0, 1), (0, 0, -1)]:
                nx, ny, nz = x + dx, y + dy, z + dz
                if not view.is_loaded(nx, ny, nz):
                    continue
                neighbor_block = view.get_block(nx, ny, nz)
                if neighbor_block not in (BlockType.AIR, BlockType.WATER):
                    continue  # Not passable
                new_cost = current_cost + 1
                if new_cost > MAX_HORIZONTAL_SPREAD:
                    continue
                cell = (nx, ny, nz)
                if cell not in dist or new_cost < dist[cell]:
                    dist[cell] = new_cost
                    queue.append(cell)
    
    # Build result: cells with cost <= MAX_HORIZONTAL_SPREAD become water
    result = {}
    for cell, cost in dist.items():
        if cost <= MAX_HORIZONTAL_SPREAD:
            result[cell] = MAX_LEVEL - cost
    
    return result
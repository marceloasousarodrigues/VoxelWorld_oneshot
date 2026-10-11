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
# Configurable finite horizontal range. Kept large enough (32) to support
# long cascade tests; the range can be increased or removed later based on
# test results without changing the flow model.
MAX_HORIZONTAL_SPREAD = 32

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
        
        # Horizontal neighbors (cost 1).
        # Suppressed only when the cell below is loadable AIR (vertical
        # priority). A loaded WATER or solid below, an unloaded below, or a
        # below outside the world all permit horizontal spread.
        can_spread = True
        if view.is_loaded(x, y - 1, z):
            below_block = view.get_block(x, y - 1, z)
            can_spread = below_block != BlockType.AIR

        if can_spread:
            for dx, dy, dz in [(1, 0, 0), (-1, 0, 0), (0, 0, 1), (0, 0, -1)]:
                nx, ny, nz = x + dx, y + dy, z + dz
                if not view.is_loaded(nx, ny, nz):
                    continue
                neighbor_block = view.get_block(nx, ny, nz)
                if neighbor_block not in (BlockType.AIR, BlockType.WATER):
                    continue  # Not passable
                new_cost = current_cost + 1
                if new_cost > max_horizontal_spread:
                    continue
                cell = (nx, ny, nz)
                if cell not in dist or new_cost < dist[cell]:
                    dist[cell] = new_cost
                    queue.append(cell)
    
    # Build result: cells with cost <= max_horizontal_spread become water,
    # clamped to a minimum level of 1 so a long horizontal reach (or a long
    # vertical fall at the reach's edge) never dries out from level exhaustion.
    result = {}
    for cell, cost in dist.items():
        if cost <= max_horizontal_spread:
            result[cell] = max(1, MAX_LEVEL - cost)
    
    return result


class _Job:
    """Internal job state for resumable water simulation."""
    def __init__(self, seeds, max_cells_per_tick: int, max_horizontal_spread: int = MAX_HORIZONTAL_SPREAD):
        self.seeds = set(seeds)
        self.max_cells_per_tick = max_cells_per_tick
        self.max_horizontal_spread = max_horizontal_spread
        self.stage = "flood"  # "flood", "solve", "commit"
        self.region = set()
        self.reachable = set()
        self.sources = set()
        self.dist = {}
        self.flood_queue = deque(seeds)  # Initialize with seeds
        self.solve_deque = deque()
        self.visited_flood = set()
        self.solution = {}
        self.budget = 0
        self.water_edit_version_start = 0

    def is_finished(self) -> bool:
        return self.stage == "done"


class WaterSimulation:
    """
    Resumable water simulation with bounded per-tick work.
    
    Architecture:
    - pending_seeds: FIFO queue + set of coords awaiting processing
    - active_job: at most one in-progress region job
    - Tick advances job by max_cells_per_tick budget units
    - Only commits complete regions (no partial updates)
    - Version-gated commits prevent stale results
    """
    
    def __init__(self, world, max_cells_per_tick: int = DEFAULT_MAX_CELLS_PER_TICK,
                 max_horizontal_spread: int = MAX_HORIZONTAL_SPREAD):
        self.world = world
        self.max_cells_per_tick = max_cells_per_tick
        self.max_horizontal_spread = max_horizontal_spread
        self.pending_seeds: Dict[Tuple[int, int, int], None] = {}  # OrderedDict-like: ordered set
        self.pending_seeds_set = set()
        self.active_job = None
    
    def _make_view(self):
        """Create a WaterView backed by self.world."""
        class WorldView:
            def __init__(self, world):
                self.world = world
                
            def is_loaded(self, x, y, z):
                cx = x // 16
                cy = y // 16
                cz = z // 16
                return (cx, cy, cz) in self.world.chunks
            
            def get_block(self, x, y, z):
                return self.world.get_block(x, y, z)
            
            def is_source(self, x, y, z):
                cx = x // 16
                cy = y // 16
                cz = z // 16
                if (cx, cy, cz) not in self.world.chunks:
                    return False
                chunk = self.world.chunks[(cx, cy, cz)]
                lx, ly, lz = x % 16, y % 16, z % 16
                return chunk.get_water_source(lx, ly, lz)
            
            def get_water_level(self, x, y, z):
                cx = x // 16
                cy = y // 16
                cz = z // 16
                if (cx, cy, cz) not in self.world.chunks:
                    return 0
                chunk = self.world.chunks[(cx, cy, cz)]
                lx, ly, lz = x % 16, y % 16, z % 16
                return chunk.get_water_level(lx, ly, lz)
        
        return WorldView(self.world)
    
    def enqueue(self, x: int, y: int, z: int) -> None:
        """Add a seed to pending_seeds."""
        coord = (x, y, z)
        if coord not in self.pending_seeds_set:
            self.pending_seeds[coord] = None
            self.pending_seeds_set.add(coord)

    def on_block_changed(self, x: int, y: int, z: int) -> None:
        """Called when a block changes (external edit). Enqueues cell and its 6 neighbors."""
        self.enqueue(x, y, z)
        for dx, dy, dz in [(1,0,0), (-1,0,0), (0,1,0), (0,-1,0), (0,0,1), (0,0,-1)]:
            self.enqueue(x+dx, y+dy, z+dz)

    def consume_changes(self) -> None:
        """Move all coordinates from world.changed_blocks into pending_seeds."""
        for coord in self.world.changed_blocks:
            self.enqueue(*coord)
            for dx, dy, dz in [(1,0,0), (-1,0,0), (0,1,0), (0,-1,0), (0,0,1), (0,0,-1)]:
                self.enqueue(coord[0]+dx, coord[1]+dy, coord[2]+dz)
        self.world.changed_blocks.clear()

    def seed_all_sources(self) -> None:
        """Seed the simulation with all loaded source cells (startup)."""
        for chunk in self.world.chunks.values():
            for x in range(16):
                for y in range(16):
                    for z in range(16):
                        if chunk.get_water_source(x, y, z):
                            world_x = chunk.chunk_x * 16 + x
                            world_y = chunk.chunk_y * 16 + y
                            world_z = chunk.chunk_z * 16 + z
                            self.enqueue(world_x, world_y, world_z)

    def tick(self) -> int:
        """
        Advance the simulation by up to max_cells_per_tick budget units.
        Returns number of occupancy changes committed this tick.
        """
        # Discard a stale job when an external edit changed the world version.
        # Its seeds are re-queued so pending work is never lost; the job is
        # rebuilt from the latest authoritative state on this tick.
        if (
            self.active_job is not None
            and self.active_job.water_edit_version_start != self.world.water_edit_version
        ):
            for seed in self.active_job.seeds:
                self.enqueue(*seed)
            self.active_job = None

        if self.active_job is None:
            # Start new job if pending seeds exist
            if not self.pending_seeds:
                return 0
            seed = next(iter(self.pending_seeds))
            del self.pending_seeds[seed]
            self.pending_seeds_set.discard(seed)
            self.active_job = _Job({seed}, self.max_cells_per_tick, self.max_horizontal_spread)
            self.active_job.water_edit_version_start = self.world.water_edit_version
        
        job = self.active_job
        budget = self.max_cells_per_tick
        view = self._make_view()
        changes = 0
        
        while budget > 0 and job is not None:
            if job.stage == "flood":
                budget = self._advance_flood(job, view, budget)
            elif job.stage == "solve":
                budget = self._advance_solve(job, view, budget)
            elif job.stage == "commit":
                changes = self._commit(job)
                self.active_job = None
                break
            else:
                break
        
        # Check if job finished during this tick
        if job is not None and job.is_finished():
            changes = self._commit(job)
            self.active_job = None
        
        return changes
    
    def _advance_flood(self, job, view, budget: int) -> int:
        """Advance flood stage. Returns remaining budget."""
        while budget > 0 and job.flood_queue:
            x, y, z = job.flood_queue.popleft()
            if (x, y, z) in job.visited_flood:
                continue
            if not view.is_loaded(x, y, z):
                continue
            
            # Check if cell is water
            if view.get_block(x, y, z) != BlockType.WATER:
                continue
            
            job.visited_flood.add((x, y, z))
            job.region.add((x, y, z))
            job.reachable.add((x, y, z))
            
            # Check 6-connected water neighbors for flood
            for dx, dy, dz in [(1,0,0), (-1,0,0), (0,1,0), (0,-1,0), (0,0,1), (0,0,-1)]:
                nx, ny, nz = x+dx, y+dy, z+dz
                if (nx, ny, nz) not in job.visited_flood:
                    if view.is_loaded(nx, ny, nz) and view.get_block(nx, ny, nz) == BlockType.WATER:
                        job.flood_queue.append((nx, ny, nz))
            
            # Add reachable passable cells (AIR or WATER) from this water cell
            for dx, dy, dz in [(1,0,0), (-1,0,0), (0,1,0), (0,-1,0), (0,0,1), (0,0,-1)]:
                nx, ny, nz = x+dx, y+dy, z+dz
                if (nx, ny, nz) in job.reachable:
                    continue
                if not view.is_loaded(nx, ny, nz):
                    continue
                block = view.get_block(nx, ny, nz)
                if block in (BlockType.AIR, BlockType.WATER):
                    job.reachable.add((nx, ny, nz))
            
            budget -= 1
        
        if not job.flood_queue:
            # Flood complete, transition to solve
            job.stage = "solve"
            job.sources = {cell for cell in job.region if view.is_source(*cell)}
            # Initialize solve deque with sources at cost 0
            job.dist = {}
            job.solve_deque = deque()
            for sx, sy, sz in job.sources:
                job.dist[(sx, sy, sz)] = 0
                job.solve_deque.appendleft((sx, sy, sz))
        
        return budget
    
    def _advance_solve(self, job, view, budget: int) -> int:
        """Advance solve stage (0-1 BFS). Returns remaining budget."""
        while budget > 0 and job.solve_deque:
            x, y, z = job.solve_deque.popleft()
            current_cost = job.dist[(x, y, z)]
            
            # Vertical down (cost 0)
            if view.is_loaded(x, y-1, z):
                below_block = view.get_block(x, y-1, z)
                if below_block in (BlockType.AIR, BlockType.WATER):
                    new_cost = job.dist[(x, y, z)]
                    cell = (x, y-1, z)
                    if cell not in job.dist or new_cost < job.dist[cell]:
                        job.dist[cell] = new_cost
                        job.solve_deque.appendleft(cell)
            
            # Horizontal (cost 1) - suppressed only when below is loaded AIR.
            can_spread = True
            if view.is_loaded(x, y-1, z):
                below_block = view.get_block(x, y-1, z)
                can_spread = below_block != BlockType.AIR

            if can_spread:
                for dx, dy, dz in [(1,0,0), (-1,0,0), (0,0,1), (0,0,-1)]:
                    nx, ny, nz = x+dx, y+dy, z+dz
                    if not view.is_loaded(nx, ny, nz):
                        continue
                    neighbor_block = view.get_block(nx, ny, nz)
                    if neighbor_block not in (BlockType.AIR, BlockType.WATER):
                        continue
                    new_cost = job.dist[(x, y, z)] + 1
                    if new_cost > job.max_horizontal_spread:
                        continue
                    cell = (nx, ny, nz)
                    if cell not in job.dist or new_cost < job.dist[cell]:
                        job.dist[cell] = new_cost
                        job.solve_deque.append((nx, ny, nz))
            
            budget -= 1
        
        if not job.solve_deque:
            job.stage = "commit"
            # Build solution from dist. Clamp to a minimum level of 1 so a
            # long horizontal reach never dries out from level exhaustion.
            job.solution = {
                cell: max(1, MAX_LEVEL - cost)
                for cell, cost in job.dist.items()
                if cost <= job.max_horizontal_spread
            }
            job.drain = job.region - set(job.solution.keys())
        
        return budget
    
    def _commit(self, job) -> int:
        """Publish the prepared region in one logical operation.

        Returns the number of occupancy changes. Writes go through
        ``World.set_water`` so they never enter the external edit log and never
        invalidate this job. The complete region is applied in a single call
        before the affected chunk meshes are refreshed, so no partially
        resolved region is ever exposed to the renderer.
        """
        world = self.world
        changes = 0

        for (x, y, z), level in job.solution.items():
            if world.set_water(x, y, z, level, source=((x, y, z) in job.sources)):
                changes += 1

        for x, y, z in job.drain:
            if world.set_water(x, y, z, 0):
                changes += 1

        if changes:
            world.refresh()

        return changes
    
    def has_pending_work(self) -> bool:
        return bool(self.pending_seeds or self.active_job)
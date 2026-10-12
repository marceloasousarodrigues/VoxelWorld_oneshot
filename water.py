"""
Deterministic water solver for VoxelWorld.

Implements source-derived 0-1 BFS water simulation with:
- Vertical priority (downward flow takes precedence)
- Bounded horizontal spread (max 7 blocks from source)
- Source-derived levels (cost = horizontal distance from source)
- Deterministic 0-1 BFS for level computation
"""

import time as _time
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

# M15: the cell budget alone is not a time bound. A tick now also stops once
# this much wall-clock time has been spent, leaving the job resumable, so water
# can never consume a frame that interaction work needs.
DEFAULT_MAX_MILLISECONDS_PER_TICK = 8.0


def _deadline_seconds(max_milliseconds_per_tick):
    """Convert a millisecond budget to seconds, or ``None`` when unbounded."""
    if max_milliseconds_per_tick is None or max_milliseconds_per_tick <= 0:
        return None
    return max_milliseconds_per_tick / 1000.0


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
        # M15: the solved region is prepared as per-chunk write batches so the
        # preparation *and* the publication step can be spread over frames.
        # ``*_iter`` are live iterators over the solved cells: they are the
        # cursor for the budgeted preparation pass and never materialise
        # another copy of the region.
        self.solution_iter = None
        self.drain_iter = None
        self.commit_groups = {}
        self.commit_plan = []
        self.commit_cursor = 0

    def is_finished(self) -> bool:
        return self.stage == "done"


class WaterSimulation:
    """
    Resumable water simulation with bounded per-tick work.
    
    Architecture:
    - pending_seeds: FIFO queue + set of coords awaiting processing
    - active_job: at most one in-progress region job
    - Tick advances job by max_cells_per_tick budget units
    - flood and solve resume across ticks; a job only reaches the commit stage
      once its whole region is solved, so an unsolved plan publishes nothing
    - the solved region is grouped into per-chunk write batches by a budgeted
      preparation pass, and published one batch at a time; both resume across
      ticks, so no single tick pays for the whole region
    - Version-gated commits prevent stale results
    """
    
    def __init__(self, world, max_cells_per_tick: int = DEFAULT_MAX_CELLS_PER_TICK,
                 max_horizontal_spread: int = MAX_HORIZONTAL_SPREAD,
                 max_milliseconds_per_tick: float | None = DEFAULT_MAX_MILLISECONDS_PER_TICK):
        self.world = world
        self.max_cells_per_tick = max_cells_per_tick
        self.max_horizontal_spread = max_horizontal_spread
        self.max_milliseconds_per_tick = max_milliseconds_per_tick
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

    def seed_chunk_sources(self, chunk) -> int:
        """Enqueue every permanent water source in one chunk.

        M16 streaming loads chunks one at a time, so a newly loaded chunk's
        sources must join the simulation without re-seeding the whole world.
        Returns the number of source cells enqueued.
        """
        size_x = chunk.SIZE_X
        size_y = chunk.SIZE_Y
        size_z = chunk.SIZE_Z
        base_x = chunk.chunk_x * size_x
        base_y = chunk.chunk_y * size_y
        base_z = chunk.chunk_z * size_z
        sources = chunk.water_sources

        count = 0
        for x in range(size_x):
            for y in range(size_y):
                for z in range(size_z):
                    if sources[x, y, z]:
                        self.enqueue(base_x + x, base_y + y, base_z + z)
                        count += 1
        return count

    def seed_all_sources(self) -> None:
        """Seed the simulation with all loaded source cells (startup)."""
        for chunk in self.world.chunks.values():
            self.seed_chunk_sources(chunk)

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

        # M15 time budget: stop advancing once this much time has been spent.
        # The outer loop always runs at least one stage call, and the stage
        # loops always consume at least one unit, so progress is guaranteed.
        started = _time.perf_counter()
        deadline = _deadline_seconds(self.max_milliseconds_per_tick)
        time_budget = (started, deadline) if deadline is not None else None
        
        while budget > 0 and job is not None:
            if deadline is not None and _time.perf_counter() - started >= deadline:
                break
            if job.stage == "flood":
                budget = self._advance_flood(job, view, budget, time_budget)
            elif job.stage == "solve":
                budget = self._advance_solve(job, view, budget, time_budget)
            elif job.stage == "prepare":
                budget = self._advance_prepare(job, budget, time_budget)
            elif job.stage == "commit":
                # M15: publication is resumable. One tick applies as many chunk
                # batches as fit in the remaining budget; the plan simply
                # continues on the next tick, and the job stays pending (and so
                # keeps `has_pending_work()` true) until every batch is applied.
                finished, committed = self._advance_commit(job, time_budget)
                changes += committed
                if finished:
                    job.stage = "done"
                    self.active_job = None
                break
            else:
                break

        return changes
    
    def _advance_flood(self, job, view, budget: int, time_budget=None) -> int:
        """Advance flood stage. Returns remaining budget.

        ``time_budget`` is ``(start_time, deadline_seconds)``; the stage stops
        early once the deadline passes, leaving the rest of the queue for the
        next tick. At least one unit is always processed.
        """
        processed = 0
        while budget > 0 and job.flood_queue:
            if processed and time_budget is not None:
                start, deadline = time_budget
                if _time.perf_counter() - start >= deadline:
                    break
            processed += 1
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
    
    def _advance_solve(self, job, view, budget: int, time_budget=None) -> int:
        """Advance solve stage (0-1 BFS). Returns remaining budget.

        Stops early once ``time_budget``'s deadline passes; the remaining deque
        is resumed next tick. At least one unit is always processed.
        """
        processed = 0
        while budget > 0 and job.solve_deque:
            if processed and time_budget is not None:
                start, deadline = time_budget
                if _time.perf_counter() - start >= deadline:
                    break
            processed += 1
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
            # Build solution from dist. Clamp to a minimum level of 1 so a
            # long horizontal reach never dries out from level exhaustion.
            job.solution = {
                cell: max(1, MAX_LEVEL - cost)
                for cell, cost in job.dist.items()
                if cost <= job.max_horizontal_spread
            }
            job.drain = job.region - set(job.solution.keys())
            # M15: grouping the solved cells into per-chunk batches is itself
            # region-proportional, so it is a budgeted stage of its own. The
            # live iterators are the cursor; they hold no extra copy.
            job.stage = "prepare"
            job.solution_iter = iter(job.solution.items())
            job.drain_iter = iter(job.drain)
            job.commit_groups = {}
        
        return budget

    def _next_prepared_cell(self, job):
        """Next ``(x, y, z, level, source)`` from the solved region, or ``None``."""
        if job.solution_iter is not None:
            item = next(job.solution_iter, None)
            if item is not None:
                (x, y, z), level = item
                return (x, y, z, level, (x, y, z) in job.sources)
            job.solution_iter = None
        if job.drain_iter is not None:
            cell = next(job.drain_iter, None)
            if cell is not None:
                x, y, z = cell
                return (x, y, z, 0, False)
            job.drain_iter = None
        return None

    def _advance_prepare(self, job, budget: int, time_budget=None) -> int:
        """Group the solved region into per-chunk write batches. Returns budget.

        Region-proportional, so it follows the flood/solve convention: pull
        solved cells until the tick deadline passes, keep the rest for the next
        tick. Nothing is published until every cell is grouped, so a partially
        prepared plan still writes nothing to the world.

        A batch is one chunk's worth of cells, and a batch is applied in a
        single vectorised step (``World.apply_water_batch``), so publication is
        atomic *per chunk*: no observer sees a chunk whose water metadata
        disagrees with its block occupancy. Batch order is the sorted chunk key,
        so repeated runs publish the identical sequence of intermediate states.
        """
        processed = 0
        while budget > 0:
            if processed and time_budget is not None:
                start, deadline = time_budget
                if _time.perf_counter() - start >= deadline:
                    break
            entry = self._next_prepared_cell(job)
            if entry is None:
                break
            processed += 1
            budget -= 1
            key = (entry[0] // 16, entry[1] // 16, entry[2] // 16)
            job.commit_groups.setdefault(key, []).append(entry)

        if job.solution_iter is None and job.drain_iter is None:
            job.commit_plan = [
                (key, job.commit_groups[key]) for key in sorted(job.commit_groups)
            ]
            job.commit_groups = {}
            job.commit_cursor = 0
            job.stage = "commit"

        return budget
    
    def _advance_commit(self, job, time_budget=None):
        """Publish the next chunk batches of a solved region.

        Returns ``(finished, changes)``. Batches are applied until the tick's
        deadline passes; at least one batch is always applied while the plan is
        unexhausted, so a commit always makes progress and can never stall.

        Frame cost is therefore bounded by the tick deadline plus one chunk
        batch (a batch is one chunk's worth of cells applied in bulk). The plan
        is written through ``World`` so dirty tracking, neighbour invalidation
        and mesh scheduling stay exactly as they are for a single-cell edit; the
        mesh rebuild itself is left to the frame loop's bounded ``reconcile``,
        which is what keeps a committing tick from also paying for geometry.
        """
        world = self.world
        changes = 0
        processed = 0
        plan = job.commit_plan
        while job.commit_cursor < len(plan):
            if processed and time_budget is not None:
                start, deadline = time_budget
                if _time.perf_counter() - start >= deadline:
                    break
            chunk_key, cells = plan[job.commit_cursor]
            job.commit_cursor += 1
            processed += 1
            changes += world.apply_water_batch(chunk_key, cells)
        
        return job.commit_cursor >= len(plan), changes
    
    def has_pending_work(self) -> bool:
        return bool(self.pending_seeds or self.active_job)
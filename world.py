"""
World container for VoxelWorld.
Manages multiple chunks and coordinates generation, loading, unloading,
and updating of chunks.
"""

from collections import defaultdict
import time as _time

import numpy as np

from chunk import Chunk
from coordinate_system import get_chunk_containing_world_coords, chunk_to_world_coords
from block_data import BlockType, is_block_solid


class World:
    """
    Manages the entire voxel world state including chunks.
    
    This class handles loading/unloading of chunks at runtime,
    maintaining world state for terrain generation, and provides 
    methods for world access and modification.
    """
    
    # M15: bounded per-frame mesh work. Rebuilding one chunk's mesh and its
    # entity is several milliseconds, so ``reconcile`` spends at most this much
    # time per frame and leaves the rest of the dirty set queued for the next
    # frame. One chunk may overrun the budget (a single rebuild always runs).
    DEFAULT_MESH_BUDGET_MS = 8.0

    def __init__(self, mesh_budget_ms=None):
        """Initialize empty world."""
        # Dictionary to store loaded chunks by chunk coordinates
        self.chunks = {}
        
        # Store chunks that have been modified and need mesh regeneration
        self.dirty_chunks = set()
        
        # Water edit version - incremented on external occupancy changes
        self.water_edit_version = 0

        # External block edits awaiting water re-evaluation (world coordinates)
        self.changed_blocks = set()

        # M15 deferred reconcile state.
        self.mesh_budget_ms = (
            self.DEFAULT_MESH_BUDGET_MS
            if mesh_budget_ms is None
            else float(mesh_budget_ms)
        )
        # The chunk most recently edited is rebuilt first so the player's own
        # interaction is never the work that gets deferred.
        self.recent_edit_chunk = None
        # Cheap integer counters on an already-taken path (no timers, no I/O).
        self.rebuild_count = 0
        self.reconcile_calls = 0
        
    def dirty(self, chunk_id):
        """Mark chunk for mesh regeneration."""
        self.dirty_chunks.add(chunk_id)
        
    def refresh(self):
        """Refresh all dirty chunks by regenerating their meshes and updating entities.

        This is the synchronous, unbounded API. It is deliberately unchanged
        (M15): every existing caller and test keeps working. The frame loop uses
        the bounded ``reconcile`` instead.
        """
        for chunk_key in list(self.dirty_chunks):
            if chunk_key in self.chunks:
                self.chunks[chunk_key].refresh(world=self)
        self.dirty_chunks.clear()

    def _order_dirty_chunks(self):
        """Deterministic rebuild order: the edited chunk first, then by coordinate."""
        keys = set(self.dirty_chunks)
        ordered = []
        recent = self.recent_edit_chunk
        if recent is not None and recent in keys:
            ordered.append(recent)
            keys.discard(recent)
        ordered.extend(sorted(keys))
        return ordered

    def reconcile(self, budget_ms=None) -> int:
        """Rebuild dirty chunk meshes within a per-frame time budget.

        Chunks are rebuilt one at a time, most-recent-edit chunk first, until
        the budget would be exceeded; the remaining chunks stay in
        ``dirty_chunks`` for the next frame. At least one chunk is always
        rebuilt when work is pending, so the queue cannot starve.

        Returns the number of chunks rebuilt in this call.
        """
        if not self.dirty_chunks:
            return 0

        budget_ms = self.mesh_budget_ms if budget_ms is None else float(budget_ms)
        ordered = self._order_dirty_chunks()

        rebuilt = 0
        elapsed_ms = 0.0
        for chunk_key in ordered:
            if chunk_key not in self.dirty_chunks:
                continue
            # Cap the work, but never refuse to make progress: the first
            # rebuild of a reconcile always runs (and it is the edited chunk).
            if rebuilt > 0 and elapsed_ms >= budget_ms:
                break
            chunk = self.chunks.get(chunk_key)
            self.dirty_chunks.discard(chunk_key)
            if chunk is None:
                continue
            started = _time.perf_counter()
            chunk.refresh(world=self)
            elapsed_ms += (_time.perf_counter() - started) * 1000.0
            rebuilt += 1

        self.rebuild_count += rebuilt
        self.reconcile_calls += 1
        return rebuilt
        
    def get_chunk(self, chunk_x: int, chunk_y: int, chunk_z: int) -> Chunk:
        """
        Get a chunk from the world, loading it if necessary.
        
        If a chunk is not already loaded, it will be created with default air blocks.
        
        Args:
            chunk_x: X coordinate of the chunk
            chunk_y: Y coordinate of the chunk  
            chunk_z: Z coordinate of the chunk
            
        Returns:
            Chunk object at the given coordinates
        """
        # Check if chunk is already loaded
        chunk_key = (chunk_x, chunk_y, chunk_z)
        if chunk_key in self.chunks:
            return self.chunks[chunk_key]
            
        # Create new chunk if needed
        new_chunk = Chunk(chunk_x, chunk_y, chunk_z)
        self.chunks[chunk_key] = new_chunk
        return new_chunk
        
    def get_block(self, world_x: int, world_y: int, world_z: int) -> int:
        """
        Get the block type at a world coordinate.
        
        Args:
            world_x: X coordinate in world space
            world_y: Y coordinate in world space
            world_z: Z coordinate in world space
            
        Returns:
            BlockType at the specified coordinates
        """
        # Convert to chunk and local coordinates
        chunk_x, chunk_y, chunk_z = get_chunk_containing_world_coords(world_x, world_y, world_z)
        local_x, local_y, local_z = world_x - (chunk_x * 16), world_y - (chunk_y * 16), world_z - (chunk_z * 16)
        
        # A read must never generate a chunk as a side effect. Serving reads by
        # creating an empty chunk made "is this chunk generated" checks answer
        # yes for the phantom chunks those same reads produced, which let the
        # player walk out of the generated world and fall forever.
        chunk = self.chunks.get((chunk_x, chunk_y, chunk_z))
        if chunk is None:
            return int(BlockType.AIR)
        return int(chunk.get_block(local_x, local_y, local_z))
        
    def is_loaded(self, world_x: int, world_y: int, world_z: int) -> bool:
        """Return True when the chunk containing the coordinate is loaded."""
        chunk_x, chunk_y, chunk_z = get_chunk_containing_world_coords(
            world_x, world_y, world_z
        )
        return (chunk_x, chunk_y, chunk_z) in self.chunks

    def get_water(self, world_x: int, world_y: int, world_z: int) -> int:
        """Return the water level at a world coordinate (0 when unloaded/dry)."""
        chunk_x, chunk_y, chunk_z = get_chunk_containing_world_coords(
            world_x, world_y, world_z
        )
        chunk = self.chunks.get((chunk_x, chunk_y, chunk_z))
        if chunk is None:
            return 0
        local_x = world_x - (chunk_x * 16)
        local_y = world_y - (chunk_y * 16)
        local_z = world_z - (chunk_z * 16)
        return chunk.get_water_level(local_x, local_y, local_z)

    def is_source(self, world_x: int, world_y: int, world_z: int) -> bool:
        """Return True when the world coordinate is a permanent water source."""
        chunk_x, chunk_y, chunk_z = get_chunk_containing_world_coords(
            world_x, world_y, world_z
        )
        chunk = self.chunks.get((chunk_x, chunk_y, chunk_z))
        if chunk is None:
            return False
        local_x = world_x - (chunk_x * 16)
        local_y = world_y - (chunk_y * 16)
        local_z = world_z - (chunk_z * 16)
        return chunk.get_water_source(local_x, local_y, local_z)

    def _mark_dirty_with_neighbors(self, chunk_x, chunk_y, chunk_z, local_x, local_y, local_z) -> None:
        """Mark a chunk and its loaded boundary neighbours dirty."""
        self.dirty_chunks.add((chunk_x, chunk_y, chunk_z))
        # M15: remember the edited chunk so the next reconcile rebuilds it first.
        self.recent_edit_chunk = (chunk_x, chunk_y, chunk_z)

        if local_x == 0 and (chunk_x - 1, chunk_y, chunk_z) in self.chunks:
            self.dirty_chunks.add((chunk_x - 1, chunk_y, chunk_z))
        elif local_x == 15 and (chunk_x + 1, chunk_y, chunk_z) in self.chunks:
            self.dirty_chunks.add((chunk_x + 1, chunk_y, chunk_z))

        if local_y == 0 and (chunk_x, chunk_y - 1, chunk_z) in self.chunks:
            self.dirty_chunks.add((chunk_x, chunk_y - 1, chunk_z))
        elif local_y == 15 and (chunk_x, chunk_y + 1, chunk_z) in self.chunks:
            self.dirty_chunks.add((chunk_x, chunk_y + 1, chunk_z))

        if local_z == 0 and (chunk_x, chunk_y, chunk_z - 1) in self.chunks:
            self.dirty_chunks.add((chunk_x, chunk_y, chunk_z - 1))
        elif local_z == 15 and (chunk_x, chunk_y, chunk_z + 1) in self.chunks:
            self.dirty_chunks.add((chunk_x, chunk_y, chunk_z + 1))

    def set_block(self, world_x: int, world_y: int, world_z: int, block_type: int) -> None:
        """
        Set the block type at a world coordinate.

        External edits clear the cell's water metadata, are recorded in the
        external-edit log, and invalidate active water jobs when they change
        the cell's occupancy or water-relevant passability.

        Args:
            world_x: X coordinate in world space
            world_y: Y coordinate in world space
            world_z: Z coordinate in world space
            block_type: BlockType to set at that location
        """
        # Convert to chunk and local coordinates
        chunk_x, chunk_y, chunk_z = get_chunk_containing_world_coords(world_x, world_y, world_z)
        local_x, local_y, local_z = world_x - (chunk_x * 16), world_y - (chunk_y * 16), world_z - (chunk_z * 16)

        # Get chunk and check old block type for occupancy change detection
        chunk = self.get_chunk(chunk_x, chunk_y, chunk_z)
        old_block = chunk.get_block(local_x, local_y, local_z)

        # An external edit discards any simulation metadata for this cell.
        chunk.set_water_level(local_x, local_y, local_z, 0)
        chunk.set_water_source(local_x, local_y, local_z, False)
        chunk.set_block(local_x, local_y, local_z, block_type)

        # M14 vegetation: an edit invalidates any decoration in the edited cell
        # (a placed block must not contain a tuft) and, when the new block cannot
        # support a plant, the decoration directly above it, so a tuft never
        # floats once its support is removed.
        chunk.clear_decoration(local_x, local_y, local_z)
        if not is_block_solid(block_type) and local_y + 1 < Chunk.SIZE_Y:
            chunk.clear_decoration(local_x, local_y + 1, local_z)

        if old_block != block_type:
            self.changed_blocks.add((world_x, world_y, world_z))
            water_relevant = (
                old_block in (BlockType.AIR, BlockType.WATER)
                or block_type in (BlockType.AIR, BlockType.WATER)
            )
            if water_relevant:
                self.water_edit_version += 1

        self._mark_dirty_with_neighbors(
            chunk_x, chunk_y, chunk_z, local_x, local_y, local_z
        )

    def set_water(
        self,
        world_x: int,
        world_y: int,
        world_z: int,
        level: int,
        source: bool = False,
    ) -> bool:
        """
        Set water level/source metadata through the simulation interface.

        Returns True when occupancy changed between AIR and WATER. Never
        creates a chunk, never writes to the external-edit log, and never
        invalidates its own simulation job.
        """
        if world_y < 0:
            return False

        chunk_x, chunk_y, chunk_z = get_chunk_containing_world_coords(world_x, world_y, world_z)
        chunk = self.chunks.get((chunk_x, chunk_y, chunk_z))
        if chunk is None:
            return False

        local_x = world_x - (chunk_x * 16)
        local_y = world_y - (chunk_y * 16)
        local_z = world_z - (chunk_z * 16)

        old_block = chunk.get_block(local_x, local_y, local_z)

        if level <= 0:
            changed = old_block == BlockType.WATER
            if changed:
                chunk.set_block(local_x, local_y, local_z, BlockType.AIR)
            chunk.clear_water(local_x, local_y, local_z)
        else:
            changed = old_block != BlockType.WATER
            chunk.set_block(local_x, local_y, local_z, BlockType.WATER)
            chunk.set_water_level(local_x, local_y, local_z, level)
            chunk.set_water_source(local_x, local_y, local_z, bool(source))

        if changed:
            self._mark_dirty_with_neighbors(
                chunk_x, chunk_y, chunk_z, local_x, local_y, local_z
            )

        return changed

    def apply_water_batch(self, chunk_key, cells) -> int:
        """Apply prepared water writes for one chunk as a single publication.

        ``chunk_key`` is the target chunk and ``cells`` an iterable of
        ``(world_x, world_y, world_z, level, source)`` tuples, all belonging to
        that chunk. This is the batch form of ``set_water``: same rules (never
        creates a chunk, never writes to the external-edit log, never
        invalidates a water job, skips ``world_y < 0``), same dirty tracking, but
        the cells land in one vectorised write so a chunk is never observable
        with half its batch applied.

        Returns the number of occupancy changes. Marks the chunk dirty, plus
        each boundary neighbour the *changed* cells actually touch.
        """
        chunk = self.chunks.get(chunk_key)
        if chunk is None:
            return 0

        chunk_x, chunk_y, chunk_z = chunk_key
        origin_x = chunk_x * Chunk.SIZE_X
        origin_y = chunk_y * Chunk.SIZE_Y
        origin_z = chunk_z * Chunk.SIZE_Z

        local_x = []
        local_y = []
        local_z = []
        levels = []
        sources = []
        for world_x, world_y, world_z, level, source in cells:
            if world_y < 0:
                continue
            x = world_x - origin_x
            y = world_y - origin_y
            z = world_z - origin_z
            if not (0 <= x < Chunk.SIZE_X and 0 <= y < Chunk.SIZE_Y and 0 <= z < Chunk.SIZE_Z):
                continue
            local_x.append(x)
            local_y.append(y)
            local_z.append(z)
            levels.append(level)
            sources.append(bool(source))

        if not local_x:
            return 0

        coords = np.array([local_x, local_y, local_z], dtype=np.intp)
        changed = chunk.apply_water_cells(
            coords[0],
            coords[1],
            coords[2],
            np.array(levels, dtype=np.int8),
            np.array(sources, dtype=bool),
        )
        changes = int(changed.sum())
        if changes == 0:
            return 0

        # Invalidate the chunk itself and every face the changed cells touch,
        # using the same rule as a single-cell edit. One representative cell per
        # face keeps this O(1) per chunk instead of O(cells).
        changed_coords = coords[:, changed]
        representatives = [(1, 1, 1)]
        for axis, size in enumerate((Chunk.SIZE_X, Chunk.SIZE_Y, Chunk.SIZE_Z)):
            column = changed_coords[axis]
            for boundary in (0, size - 1):
                if (column == boundary).any():
                    cell = [1, 1, 1]
                    cell[axis] = boundary
                    representatives.append(tuple(cell))

        for local_x_cell, local_y_cell, local_z_cell in representatives:
            self._mark_dirty_with_neighbors(
                chunk_x, chunk_y, chunk_z, local_x_cell, local_y_cell, local_z_cell
            )

        return changes
        
    def get_chunk_coords_containing_world_coords(self, world_x: int, world_y: int, world_z: int) -> tuple[int, int, int]:
        """
        Get the chunk coordinates that contain the given world coordinates.
        
        Args:
            world_x: X coordinate in world space
            world_y: Y coordinate in world space
            world_z: Z coordinate in world space
            
        Returns:
            Tuple of (chunk_x, chunk_y, chunk_z) coordinates
        """
        return get_chunk_containing_world_coords(world_x, world_y, world_z)
        
    def generate_initial_terrain(self) -> None:
        """
        Generate initial terrain for the world.
        
        This creates a flat world with grass at the surface level (y=0),
        dirt below it, and stone below that. 
        """
        # Create a simple flattened world based on height levels
        # For this implementation we'll generate a deterministic flat terrain
        
        # Generate multiple chunks around origin to show terrain generation
        # In a real implementation, we'd have a larger world with more chunks
        for chunk_x in range(-1, 2):
            for chunk_z in range(-1, 2):
                chunk = self.get_chunk(chunk_x, 0, chunk_z)
                
                # Generate blocks in this chunk based on position
                for x in range(Chunk.SIZE_X):
                    for z in range(Chunk.SIZE_Z):
                        # Calculate world coordinates for this block
                        global_x = chunk_x * Chunk.SIZE_X + x
                        global_z = chunk_z * Chunk.SIZE_Z + z
                        
                        # For flat terrain, set blocks based on position
                        for y in range(Chunk.SIZE_Y):
                            if y == 0:
                                # Surface layer of grass (at y=15)
                                chunk.set_block(x, y, z, BlockType.GRASS)  # Grass at top
                            elif y < 5:
                                # Dirt layer (4 layers below)
                                chunk.set_block(x, y, z, BlockType.DIRT)  # Dirt
                            elif y < 16:
                                # Stone layer at bottom
                                chunk.set_block(x, y, z, BlockType.STONE)  # Stone
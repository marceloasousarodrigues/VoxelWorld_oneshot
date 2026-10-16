class_name FluidSim
extends RefCounted

## Bounded, event-driven water simulation.
##
## Model
## -----
## * Every water cell carries an integer level 1..8 (8 = source).  Fluid state is
##   authoritative and independent of the rendered surface; the mesher derives
##   the visible water height from the level.
## * Levels are fed-derived: a cell resting on ground takes
##   `max(horizontal neighbour level) - 1`, and a cell that is not fed loses one
##   level per evaluation.  Water therefore spreads a bounded number of blocks
##   away from its source and, once the source is gone, drains away completely.
## * Vertical movement has priority: a cell that is fed from above is
##   full-strength, and only water standing on the ground pushes sideways, so a
##   falling column does not fan out into a cone.
## * Water standing over open air is only kept where water spills into it from a
##   neighbouring body with pressure, which prevents both stagnant floating pools
##   and oceans draining through cave mouths.
##
## Scheduling
## ----------
## The simulation is a work queue of *cells*, not a global solve.  Every change
## enqueues only the affected cell and its six neighbours, each tick processes a
## bounded number of cells within a wall-clock budget, and each cell is evaluated
## against the current authoritative world state.  There is therefore no long
## running plan that a later edit could invalidate: a player edit simply enqueues
## its own cells and wins immediately.

const MAX_LEVEL := 8
const SOURCE_LEVEL := 8
const FALLING_LEVEL := 7
const MIN_LEVEL := 1
## Documented horizontal reach: levels run 8 -> 1, so water from a source stops
## after seven horizontal steps.
const MAX_SPREAD := 7

const DEFAULT_MAX_CELLS_PER_TICK := 4096
const DEFAULT_MAX_MILLISECONDS_PER_TICK := 3.0

const NEIGHBOURS := [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0),
	Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]
const HORIZONTAL := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]

var world: VoxelWorld
var max_cells_per_tick := DEFAULT_MAX_CELLS_PER_TICK
var max_milliseconds_per_tick := DEFAULT_MAX_MILLISECONDS_PER_TICK

var _queue: Array[Vector3i] = []
var _head := 0
var _queued: Dictionary = {}
var _changes := 0
var _evaluations := 0
var _seeded_chunks := 0
var observed_edits := 0


func _init(target_world: VoxelWorld) -> void:
	world = target_world


# --- scheduling -----------------------------------------------------------

func enqueue(position: Vector3i) -> bool:
	if _queued.has(position):
		return false
	if not VoxelWorld.in_world_vertical(position.y):
		return false
	_queued[position] = true
	_queue.append(position)
	return true


func enqueue_with_neighbours(position: Vector3i) -> void:
	enqueue(position)
	for offset in NEIGHBOURS:
		enqueue(position + offset)


## Called when the world (including the player) changed a block.
func on_block_changed(position: Vector3i, _previous: int, _current: int) -> void:
	observed_edits += 1
	enqueue_with_neighbours(position)


func pending_count() -> int:
	return _queue.size() - _head


func has_pending_work() -> bool:
	return pending_count() > 0


## Registers the permanent sources of a freshly loaded chunk plus the empty cells
## that water could flow into, so a chunk that appears at the edge of the loaded
## world keeps flowing across the boundary.
func seed_chunk_sources(chunk: ChunkData) -> int:
	var base := VoxelWorld.chunk_origin(chunk.coord)
	var counted := 0
	for index in ChunkData.CELLS:
		if chunk.blocks[index] != BlockDB.WATER:
			continue
		var local := ChunkData.index_to_local(index)
		var world_position := base + local
		var touches_air := false
		for offset in NEIGHBOURS:
			var neighbour: Vector3i = world_position + offset
			var block_id := world.get_block(neighbour)
			if block_id == BlockDB.AIR:
				touches_air = true
				enqueue(neighbour)
		if touches_air or chunk.sources[index] == 1:
			enqueue(world_position)
			if chunk.sources[index] == 1:
				counted += 1
	_seeded_chunks += 1
	return counted


func seed_around(position: Vector3i, radius: int = 2) -> int:
	var counted := 0
	for dy in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var probe := position + Vector3i(dx, dy, dz)
				if world.is_water_source(probe):
					enqueue(probe)
					counted += 1
	return counted


# --- tick -----------------------------------------------------------------

## Processes at most `max_cells_per_tick` cells and stops early once the
## per-tick wall-clock budget is exhausted.  Returns the number of cells whose
## level changed.
func tick() -> int:
	if not has_pending_work():
		return 0
	var started := Time.get_ticks_usec()
	var budget := max_cells_per_tick
	var changed := 0
	var since_check := 0
	var deadline := int(max_milliseconds_per_tick * 1000.0)
	while budget > 0 and _head < _queue.size():
		var position: Vector3i = _queue[_head]
		_head += 1
		_queued.erase(position)
		budget -= 1
		since_check += 1
		_evaluations += 1
		changed += _evaluate(position)
		if since_check >= 48:
			since_check = 0
			if Time.get_ticks_usec() - started >= deadline:
				break
	if _head > 64 and _head * 2 >= _queue.size():
		_queue = _queue.slice(_head)
		_head = 0
	elif _head >= _queue.size():
		_queue.clear()
		_head = 0
	_changes += changed
	return changed


func _evaluate(position: Vector3i) -> int:
	if not world.is_loaded(position):
		# The chunk was unloaded; its sources are re-seeded when it returns.
		return 0
	var block_id := world.get_block(position)
	if block_id != BlockDB.AIR and block_id != BlockDB.WATER:
		return 0
	var target := _target_level(position)
	var current := world.get_fluid(position)
	var is_source := world.is_water_source(position)
	if target == current:
		# Only the source flag can still be out of sync.
		if target == 0 or is_source == (target == SOURCE_LEVEL):
			return 0
	world.set_fluid(position, target, target == SOURCE_LEVEL)
	# A changed cell wakes itself and its neighbours.  A neighbour that drains
	# still has to wake the cells it was holding up, and a cell that is still
	# losing one level per evaluation re-enqueues itself until it reaches its
	# fixpoint, so a removed source empties its pool completely inside the
	# per-tick budget instead of stalling with stranded half-levels.
	enqueue_with_neighbours(position)
	return 1


## Target level for one cell, derived only from the current authoritative state
## of the cell and its six neighbours.
func _target_level(position: Vector3i) -> int:
	if world.is_water_source(position):
		return SOURCE_LEVEL
	# Vertical priority: anything with water directly above is full-strength.
	if _level(position + Vector3i.UP) > 0:
		return FALLING_LEVEL
	var best := 0
	for offset in HORIZONTAL:
		var supply := _supply_level(position + offset)
		if supply > best:
			best = supply
	if not _is_supported(position):
		# A cell over open air is only taken by water that spills in from a
		# neighbouring body with real pressure; water with nothing underneath and
		# nothing pushing it drains.  Spilled water falls, so it is full-strength.
		return FALLING_LEVEL if best > MIN_LEVEL else 0
	var target := 0
	if best > MIN_LEVEL:
		target = best - 1
	# A cell that is not being fed loses one level per evaluation, so a pool
	# whose source was removed drains instead of holding itself up through a
	# cycle of its own cells.
	var own := _level(position)
	if own > 0:
		target = maxi(target, own - 1)
	return target


## True when the cell has something other than air or water underneath, so water
## there rests on ground and can be held.
func _is_supported(position: Vector3i) -> bool:
	var below := world.get_block(position + Vector3i.DOWN)
	return below != BlockDB.AIR and below != BlockDB.WATER


## How much horizontal pressure a neighbouring water cell exerts on this cell.
##
## Water pushes sideways only when it is not itself in free fall: it must rest on
## ground, or be a source sitting on top of a body of water (an ocean the player
## digs into).  Falling water — a source hanging in mid-air, or a column on its
## way down — keeps its pressure vertical and never fans out into a cone.
func _supply_level(position: Vector3i) -> int:
	var level := _level(position)
	if level <= 0:
		return 0
	if _is_supported(position):
		return level
	if world.is_water_source(position) and world.get_block(position + Vector3i.DOWN) == BlockDB.WATER:
		return level
	return 0


func _level(position: Vector3i) -> int:
	if not world.is_loaded(position):
		return 0
	if world.get_block(position) != BlockDB.WATER:
		return 0
	return world.get_fluid(position)


# --- reporting ------------------------------------------------------------

func stats() -> Dictionary:
	return {
		"pending": pending_count(),
		"evaluations": _evaluations,
		"changes": _changes,
		"observed_edits": observed_edits,
		"seeded_chunks": _seeded_chunks,
	}


## Debug helper: current level of a cell, 0 when dry.
func level_at(position: Vector3i) -> int:
	return _level(position)

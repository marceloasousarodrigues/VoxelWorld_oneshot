class_name VoxelWorld
extends RefCounted

const BlockShape = preload("res://scripts/core/block_shape.gd")

## Authoritative logical voxel world.
##
## Owns chunk data, world/chunk coordinate conversion (floor semantics that are
## correct for negative coordinates), player edits, fluid state and chunk
## lifecycle.  Rendering, streaming and meshing are driven by other systems that
## observe this class; nothing here knows about meshes or nodes.

signal block_changed(world_position: Vector3i, previous: int, current: int)
signal chunk_created(coord: Vector3i)
signal chunk_removed(coord: Vector3i)

const SIZE := ChunkData.SIZE
const WORLD_HEIGHT := WorldGen.WORLD_HEIGHT
const CHUNKS_Y := WorldGen.CHUNKS_Y

var world_seed: int
var generator: WorldGen
var chunks: Dictionary = {}
## Player/edits persistence: world position -> block id.
var edits: Dictionary = {}
## Edits grouped by chunk so regenerating one chunk re-applies only its own.
var edits_by_chunk: Dictionary = {}
## Orientation of each edited block; grouped separately to preserve the existing
## position -> block-id edit contract used by game systems and diagnostics.
var edit_orientations: Dictionary = {}
var edit_orientations_by_chunk: Dictionary = {}
## Fluid overrides that differ from the generated world: position -> level.
var fluid_overrides: Dictionary = {}
## The same overrides grouped by chunk so a regenerated chunk re-applies only
## its own cells instead of scanning every override in the world.
var fluid_overrides_by_chunk: Dictionary = {}
var fluid_sources: Dictionary = {}
var stats := {"generated_chunks": 0, "generation_ms": 0.0, "edits": 0, "loaded": 0}


func _init(world_seed_value: int = 17017) -> void:
	world_seed = world_seed_value
	generator = WorldGen.new(world_seed_value)


# --- coordinates ----------------------------------------------------------

static func world_to_chunk(world_position: Vector3i) -> Vector3i:
	return Vector3i(
		floori(float(world_position.x) / SIZE),
		floori(float(world_position.y) / SIZE),
		floori(float(world_position.z) / SIZE)
	)


static func world_to_local(world_position: Vector3i) -> Vector3i:
	return Vector3i(posmod(world_position.x, SIZE), posmod(world_position.y, SIZE), posmod(world_position.z, SIZE))


static func chunk_origin(coord: Vector3i) -> Vector3i:
	return coord * SIZE


static func in_world_vertical(world_y: int) -> bool:
	return world_y >= 0 and world_y < WORLD_HEIGHT


# --- chunk lifecycle ------------------------------------------------------

func has_chunk(coord: Vector3i) -> bool:
	return chunks.has(coord)


func get_chunk(coord: Vector3i) -> ChunkData:
	return chunks.get(coord, null)


## Generates the chunk if it is not loaded yet and returns it.
func ensure_chunk(coord: Vector3i) -> ChunkData:
	var existing: ChunkData = chunks.get(coord, null)
	if existing != null:
		return existing
	if coord.y < 0 or coord.y >= CHUNKS_Y:
		return null
	var started := Time.get_ticks_usec()
	var chunk := ChunkData.new(coord)
	generator.generate_chunk(chunk)
	chunks[coord] = chunk
	stats["generated_chunks"] = int(stats["generated_chunks"]) + 1
	stats["generation_ms"] = float(stats["generation_ms"]) + float(Time.get_ticks_usec() - started) / 1000.0
	_apply_saved_edits(chunk)
	_count_solid(chunk)
	chunk.mark_dirty()
	stats["loaded"] = chunks.size()
	chunk_created.emit(coord)
	return chunk


## Loads a chunk from pre-built data (background generation / shared fixture
## loading / tests).  The generation worker builds the voxels; this adopts them
## on the main thread exactly like `ensure_chunk`, so saved edits are re-applied
## and the derived state is flagged.
func adopt_chunk(chunk: ChunkData) -> void:
	chunks[chunk.coord] = chunk
	_apply_saved_edits(chunk)
	_count_solid(chunk)
	chunk.mark_dirty()
	stats["loaded"] = chunks.size()
	chunk_created.emit(chunk.coord)


func unload_chunk(coord: Vector3i) -> void:
	if not chunks.has(coord):
		return
	chunks.erase(coord)
	stats["loaded"] = chunks.size()
	chunk_removed.emit(coord)


func _count_solid(chunk: ChunkData) -> void:
	var count := 0
	var blocks := chunk.blocks
	for index in blocks.size():
		if BlockDB.is_solid(blocks[index]):
			count += 1
	chunk.solid_cells = count


# --- block access ---------------------------------------------------------

func get_block(world_position: Vector3i) -> int:
	var chunk: ChunkData = chunks.get(world_to_chunk(world_position), null)
	if chunk == null:
		return BlockDB.AIR
	var local := world_to_local(world_position)
	return chunk.blocks[ChunkData.cell_index(local.x, local.y, local.z)]


func get_orientation(world_position: Vector3i) -> int:
	var chunk: ChunkData = chunks.get(world_to_chunk(world_position), null)
	if chunk == null:
		return 0
	var local := world_to_local(world_position)
	return int(chunk.orientations[ChunkData.cell_index(local.x, local.y, local.z)])


func get_block_unloaded_as_air(world_position: Vector3i) -> int:
	return get_block(world_position)


func is_loaded(world_position: Vector3i) -> bool:
	return chunks.has(world_to_chunk(world_position))


func is_solid(world_position: Vector3i) -> bool:
	return BlockDB.is_solid(get_block(world_position))


## Sets a block, records it as a player edit and flags affected meshes.
## Returns true when the world actually changed.
func set_block(world_position: Vector3i, block_id: int, record_edit: bool = true) -> bool:
	return set_block_state(world_position, block_id, 0, record_edit)


## Sets a block and its shape orientation as one logical edit.
func set_block_state(world_position: Vector3i, block_id: int, orientation: int,
		record_edit: bool = true) -> bool:
	if not in_world_vertical(world_position.y):
		return false
	if not BlockShape.is_valid_orientation(orientation):
		return false
	if block_id != BlockDB.STAIR and orientation != 0:
		return false
	var coord := world_to_chunk(world_position)
	var chunk: ChunkData = chunks.get(coord, null)
	if chunk == null:
		return false
	var local := world_to_local(world_position)
	var index := ChunkData.cell_index(local.x, local.y, local.z)
	var previous := chunk.blocks[index]
	var previous_orientation := int(chunk.orientations[index])
	if previous == block_id and previous_orientation == orientation:
		return false
	var was_solid := BlockDB.is_solid(previous)
	var is_solid_now := BlockDB.is_solid(block_id)
	if was_solid != is_solid_now:
		chunk.solid_cells += 1 if is_solid_now else -1
	chunk.blocks[index] = block_id
	chunk.orientations[index] = orientation
	if block_id == BlockDB.WATER:
		if chunk.fluid[index] == ChunkData.NO_FLUID:
			chunk.fluid[index] = ChunkData.SOURCE_LEVEL
			chunk.sources[index] = 1
	else:
		chunk.fluid[index] = ChunkData.NO_FLUID
		chunk.sources[index] = 0
	chunk.edited = true
	chunk.mark_dirty()
	if record_edit:
		_record_edit(world_position, block_id, orientation, chunk)
	_flag_neighbours(world_position)
	block_changed.emit(world_position, previous, block_id)
	# Decoration is supported by the block below it.  Removing that support (or
	# replacing it with water) removes the plant too, so a mined grass block never
	# leaves a flower or tuft floating in the air.  Generation writes chunk arrays
	# directly, so load order is unaffected.
	if not is_solid_now and previous != block_id:
		var above := world_position + Vector3i.UP
		var above_id := get_block(above)
		if BlockDB.is_deco(above_id):
			set_block(above, BlockDB.AIR, record_edit)
	return true


func _record_edit(world_position: Vector3i, block_id: int, orientation: int, chunk: ChunkData) -> void:
	edits[world_position] = block_id
	edit_orientations[world_position] = orientation
	var key := chunk.coord
	var per_chunk: Dictionary = edits_by_chunk.get(key, {})
	per_chunk[world_position] = block_id
	edits_by_chunk[key] = per_chunk
	var per_chunk_orientation: Dictionary = edit_orientations_by_chunk.get(key, {})
	per_chunk_orientation[world_position] = orientation
	edit_orientations_by_chunk[key] = per_chunk_orientation
	stats["edits"] = edits.size()


func _apply_saved_edits(chunk: ChunkData) -> void:
	var per_chunk: Variant = edits_by_chunk.get(chunk.coord)
	if per_chunk != null:
		for position: Vector3i in (per_chunk as Dictionary):
			var local := world_to_local(position)
			var index := ChunkData.cell_index(local.x, local.y, local.z)
			var block_id: int = (per_chunk as Dictionary)[position]
			chunk.blocks[index] = block_id
			var orientations_for_chunk: Dictionary = edit_orientations_by_chunk.get(chunk.coord, {})
			chunk.orientations[index] = int(orientations_for_chunk.get(position, 0))
			if block_id != BlockDB.WATER:
				chunk.fluid[index] = ChunkData.NO_FLUID
				chunk.sources[index] = 0
			chunk.edited = true
	_apply_saved_fluid(chunk)


func _apply_saved_fluid(chunk: ChunkData) -> void:
	var per_chunk: Variant = fluid_overrides_by_chunk.get(chunk.coord)
	if per_chunk == null:
		return
	for position: Vector3i in (per_chunk as Dictionary):
		var local := world_to_local(position)
		var index := ChunkData.cell_index(local.x, local.y, local.z)
		var level: int = (per_chunk as Dictionary)[position]
		_apply_fluid_cell(chunk, index, level, fluid_sources.has(position))


# --- persistence ----------------------------------------------------------

## Replaces the persisted edit set (block edits, fluid levels and fluid sources)
## and rebuilds every loaded chunk from the seed with the new set applied.
##
## Regenerating rather than patching is what makes loading a *different* save
## safe: no edit from the previous session can survive a load.
func load_edits(block_edits: Dictionary, fluid_edits: Dictionary, fluid_source_positions: Dictionary,
		orientation_edits: Dictionary = {}) -> void:
	edits = block_edits
	edits_by_chunk = group_by_chunk(block_edits)
	edit_orientations = {}
	for position: Vector3i in block_edits:
		var orientation := int(orientation_edits.get(position, 0))
		if not BlockShape.is_valid_orientation(orientation):
			orientation = 0
		if int(block_edits[position]) != BlockDB.STAIR:
			orientation = 0
		edit_orientations[position] = orientation
	edit_orientations_by_chunk = group_by_chunk(edit_orientations)
	fluid_overrides = fluid_edits
	fluid_overrides_by_chunk = group_by_chunk(fluid_edits)
	fluid_sources = fluid_source_positions
	stats["edits"] = edits.size()
	for coord: Vector3i in chunks.keys():
		_regenerate_loaded(coord)


## Forgets every persisted edit and rebuilds the loaded chunks pristine.
func clear_edits() -> void:
	load_edits({}, {}, {}, {})


static func group_by_chunk(entries: Dictionary) -> Dictionary:
	var grouped := {}
	for position: Vector3i in entries:
		var key := world_to_chunk(position)
		var per_chunk: Dictionary = grouped.get(key, {})
		per_chunk[position] = entries[position]
		grouped[key] = per_chunk
	return grouped


func _regenerate_loaded(coord: Vector3i) -> void:
	var chunk := ChunkData.new(coord)
	generator.generate_chunk(chunk)
	_apply_saved_edits(chunk)
	_count_solid(chunk)
	chunk.mark_dirty()
	chunks[coord] = chunk
	stats["generated_chunks"] = int(stats["generated_chunks"]) + 1
	chunk_created.emit(coord)


func _apply_fluid_cell(chunk: ChunkData, index: int, level: int, is_source: bool) -> void:
	if level <= 0:
		chunk.fluid[index] = ChunkData.NO_FLUID
		chunk.sources[index] = 0
		if chunk.blocks[index] == BlockDB.WATER:
			chunk.blocks[index] = BlockDB.AIR
		return
	if chunk.blocks[index] != BlockDB.AIR and chunk.blocks[index] != BlockDB.WATER:
		return
	chunk.blocks[index] = BlockDB.WATER
	chunk.fluid[index] = level
	chunk.sources[index] = 1 if is_source else 0


## Flags the chunk and any loaded neighbour whose mesh touches this cell.
func _flag_neighbours(world_position: Vector3i) -> void:
	var local := world_to_local(world_position)
	var coord := world_to_chunk(world_position)
	var neighbours: Array[Vector3i] = []
	if local.x == 0:
		neighbours.append(Vector3i.LEFT)
	if local.x == SIZE - 1:
		neighbours.append(Vector3i.RIGHT)
	if local.y == 0:
		neighbours.append(Vector3i.DOWN)
	if local.y == SIZE - 1:
		neighbours.append(Vector3i.UP)
	# Godot's FORWARD is -Z and BACK is +Z; the negative Z face therefore touches
	# the chunk at `coord - Z`, not `coord + Z`.  Getting these two backwards
	# leaves the neighbour's newly exposed face (and its collision) missing.
	if local.z == 0:
		neighbours.append(Vector3i(0, 0, -1))
	if local.z == SIZE - 1:
		neighbours.append(Vector3i(0, 0, 1))
	for offset: Vector3i in neighbours:
		var neighbour: ChunkData = chunks.get(coord + offset, null)
		if neighbour != null:
			neighbour.mark_dirty()


# --- fluid ----------------------------------------------------------------

func get_fluid(world_position: Vector3i) -> int:
	var chunk: ChunkData = chunks.get(world_to_chunk(world_position), null)
	if chunk == null:
		return ChunkData.NO_FLUID
	var local := world_to_local(world_position)
	return chunk.fluid[ChunkData.cell_index(local.x, local.y, local.z)]


func is_water_source(world_position: Vector3i) -> bool:
	var chunk: ChunkData = chunks.get(world_to_chunk(world_position), null)
	if chunk == null:
		return false
	var local := world_to_local(world_position)
	return chunk.sources[ChunkData.cell_index(local.x, local.y, local.z)] == 1


func is_passable(world_position: Vector3i) -> bool:
	var block_id := get_block(world_position)
	return block_id == BlockDB.AIR or block_id == BlockDB.WATER


## Writes a fluid level.  Only affects cells that are air or water.
## Returns true when the world changed.
func set_fluid(world_position: Vector3i, level: int, is_source: bool, record: bool = true) -> bool:
	if not in_world_vertical(world_position.y):
		return false
	var chunk: ChunkData = chunks.get(world_to_chunk(world_position), null)
	if chunk == null:
		return false
	var local := world_to_local(world_position)
	var index := ChunkData.cell_index(local.x, local.y, local.z)
	var previous_block := chunk.blocks[index]
	var previous_level := chunk.fluid[index]
	var previous_source := chunk.sources[index]
	if previous_block != BlockDB.AIR and previous_block != BlockDB.WATER and level > 0:
		return false
	if level <= 0 and previous_block != BlockDB.WATER:
		if previous_level == 0:
			return false
	if previous_level == level and previous_source == (1 if is_source else 0):
		return false
	_apply_fluid_cell(chunk, index, level, is_source)
	chunk.mark_dirty()
	if record:
		_record_fluid(world_position, level, is_source, chunk)
		_flag_neighbours(world_position)
	stats["fluid_changes"] = int(stats.get("fluid_changes", 0)) + 1
	return true


func set_fluid_source(world_position: Vector3i, is_source: bool) -> void:
	var chunk: ChunkData = chunks.get(world_to_chunk(world_position), null)
	if chunk == null:
		return
	var local := world_to_local(world_position)
	var index := ChunkData.cell_index(local.x, local.y, local.z)
	chunk.sources[index] = 1 if is_source else 0


## Compares a fluid write against the pristine generated world so saves only
## store what the simulation or the player actually changed.
func _record_fluid(world_position: Vector3i, level: int, is_source: bool, chunk: ChunkData) -> void:
	var generated_level := _generated_fluid_level(world_position)
	var generated_source := generated_level == ChunkData.SOURCE_LEVEL
	var chunk_key := world_to_chunk(world_position)
	var per_chunk: Dictionary = fluid_overrides_by_chunk.get(chunk_key, {})
	if level == generated_level and is_source == generated_source:
		fluid_overrides.erase(world_position)
		per_chunk.erase(world_position)
		fluid_sources.erase(world_position)
	else:
		fluid_overrides[world_position] = level
		per_chunk[world_position] = level
		if is_source:
			fluid_sources[world_position] = true
		else:
			fluid_sources.erase(world_position)
	if per_chunk.is_empty():
		fluid_overrides_by_chunk.erase(chunk_key)
	else:
		fluid_overrides_by_chunk[chunk_key] = per_chunk


func _generated_fluid_level(world_position: Vector3i) -> int:
	if world_position.y > WorldGen.SEA_LEVEL:
		return ChunkData.NO_FLUID
	var height := generator.height_at(world_position.x, world_position.z)
	if world_position.y > height and world_position.y <= WorldGen.SEA_LEVEL:
		return ChunkData.SOURCE_LEVEL
	return ChunkData.NO_FLUID


# --- helpers --------------------------------------------------------------

## Chunk coordinates in a stable order, so fingerprints never depend on the order
## chunks happened to be loaded in.
static func sorted_coords(source: Dictionary) -> Array:
	var coords: Array = source.keys()
	coords.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return a < b)
	return coords


## Stable hash of every loaded chunk's logical data (blocks, shape orientation + fluid).
##
## Two runs that generate the same region must report the same value no matter
## how the streaming budgets split the work across frames.
func fingerprint() -> int:
	var hash_value := 0
	for coord: Vector3i in sorted_coords(chunks):
		var chunk: ChunkData = chunks[coord]
		hash_value = _mix(hash_value, coord.x, coord.y, coord.z)
		var blocks := chunk.blocks
		var orientations := chunk.orientations
		var fluid := chunk.fluid
		var sources := chunk.sources
		for index in ChunkData.CELLS:
			hash_value = (hash_value * 1000003 + blocks[index] * 7 + orientations[index] * 97 \
				+ fluid[index] * 131 + sources[index] * 8191) & 0x7FFFFFFFFFFFFFFF
	return hash_value


static func _mix(hash_value: int, x: int, y: int, z: int) -> int:
	var mixed := (hash_value * 1000003 + (x + 4096) * 2654435761) & 0x7FFFFFFFFFFFFFFF
	mixed = (mixed * 1000003 + (y + 4096) * 40503) & 0x7FFFFFFFFFFFFFFF
	return (mixed * 1000003 + (z + 4096) * 2246822519) & 0x7FFFFFFFFFFFFFFF


func surface_height(x: int, z: int) -> int:
	return generator.height_at(x, z)


func biome_at(x: int, z: int) -> int:
	return generator.biome_at(x, z)


func tint_for_column(x: int, z: int) -> Color:
	return generator.biome_tint(generator.biome_at(x, z))


## True when the column at this position is generated (surface known).
func clear_column_cache() -> void:
	generator._column_cache.clear()

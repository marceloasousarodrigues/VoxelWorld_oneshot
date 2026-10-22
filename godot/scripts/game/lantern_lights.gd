class_name LanternLights
extends Node3D

## Bounded warm lighting for lantern blocks.
##
## The world can contain thousands of lanterns, but only the handful near the
## player matter.  This node keeps a registry of lantern cells (updated when a
## chunk is created/unloaded or a block changes), then reuses a fixed pool of
## `OmniLight3D`s for the nearest ones.  There is never a node per lantern in the
## world, and unloading a chunk removes its lights immediately.

const MAX_LIGHTS := 12
const MAX_DISTANCE := 42.0
const REFRESH_SECONDS := 0.6

var world: VoxelWorld
var player: Node3D
var daylight := 1.0

var _lights: Array[OmniLight3D] = []
var _positions: Dictionary = {}
var _by_chunk: Dictionary = {}
var _dirty := true
var _timer := 0.0
var _scan_ms := 0.0
var _scans := 0
var _assigned := 0


func setup(target_world: VoxelWorld, target_player: Node3D) -> void:
	if world != null:
		if world.block_changed.is_connected(_on_block_changed):
			world.block_changed.disconnect(_on_block_changed)
		if world.chunk_created.is_connected(_on_chunk_created):
			world.chunk_created.disconnect(_on_chunk_created)
		if world.chunk_removed.is_connected(_on_chunk_removed):
			world.chunk_removed.disconnect(_on_chunk_removed)
	world = target_world
	player = target_player
	_positions.clear()
	_by_chunk.clear()
	_dirty = true
	for coord: Vector3i in world.chunks.keys():
		_scan_chunk(coord)
	world.block_changed.connect(_on_block_changed)
	world.chunk_created.connect(_on_chunk_created)
	world.chunk_removed.connect(_on_chunk_removed)


func _process(delta: float) -> void:
	_timer += delta
	if _dirty or _timer >= REFRESH_SECONDS:
		_timer = 0.0
		_dirty = false
		refresh()


func set_daylight(value: float) -> void:
	daylight = clampf(value, 0.0, 1.0)
	_apply_energy()


func stats() -> Dictionary:
	return {
		"tracked": _positions.size(),
		"lights": _lights.size(),
		"assigned": _assigned,
		"scans": _scans,
		"scan_ms": _scan_ms,
	}


# --- registry -------------------------------------------------------------

func _on_chunk_created(coord: Vector3i) -> void:
	_scan_chunk(coord)
	_dirty = true


func _on_chunk_removed(coord: Vector3i) -> void:
	var entries: Array = _by_chunk.get(coord, [])
	for position: Vector3i in entries:
		_positions.erase(position)
	_by_chunk.erase(coord)
	_dirty = true


func _on_block_changed(position: Vector3i, previous: int, current: int) -> void:
	var coord := VoxelWorld.world_to_chunk(position)
	var entries: Array = _by_chunk.get(coord, [])
	var had := entries.has(position)
	if current == BlockDB.LANTERN:
		_positions[position] = true
		if not had:
			entries.append(position)
	elif had:
		_positions.erase(position)
		entries.erase(position)
	if entries.is_empty():
		_by_chunk.erase(coord)
	else:
		_by_chunk[coord] = entries
	if previous == BlockDB.LANTERN or current == BlockDB.LANTERN:
		_dirty = true


func _scan_chunk(coord: Vector3i) -> void:
	var chunk := world.get_chunk(coord)
	if chunk == null:
		return
	var started := Time.get_ticks_usec()
	var entries: Array = _by_chunk.get(coord, [])
	var blocks := chunk.blocks
	for index in ChunkData.CELLS:
		if int(blocks[index]) != BlockDB.LANTERN:
			continue
		var local_x := index % ChunkData.SIZE
		var local_z := (index / ChunkData.SIZE) % ChunkData.SIZE
		var local_y := index / (ChunkData.SIZE * ChunkData.SIZE)
		var position := coord * ChunkData.SIZE + Vector3i(local_x, local_y, local_z)
		_positions[position] = true
		entries.append(position)
	_by_chunk[coord] = entries
	_scan_ms += float(Time.get_ticks_usec() - started) / 1000.0
	_scans += 1


# --- light pool -----------------------------------------------------------

func refresh() -> void:
	if world == null:
		return
	var origin := player.global_position if player != null else global_position
	var candidates: Array = []
	for position: Vector3i in _positions:
		var centre := Vector3(position) + Vector3(0.5, 0.3, 0.5)
		var distance := origin.distance_to(centre)
		if distance <= MAX_DISTANCE:
			candidates.append([distance, centre])
	candidates.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var count := mini(candidates.size(), MAX_LIGHTS)
	_ensure_pool(count)
	for index in _lights.size():
		var light := _lights[index]
		if index >= count:
			light.visible = false
			continue
		light.visible = true
		light.global_position = candidates[index][1]
	_assigned = count
	_apply_energy()


func _ensure_pool(count: int) -> void:
	while _lights.size() < count:
		var light := OmniLight3D.new()
		light.name = "LanternLight%d" % _lights.size()
		light.light_color = Color(1.0, 0.62, 0.28)
		light.omni_range = 9.0
		light.omni_attenuation = 1.6
		light.shadow_enabled = false
		light.distance_fade_enabled = true
		light.distance_fade_begin = 30.0
		light.distance_fade_length = 14.0
		add_child(light)
		_lights.append(light)


func _apply_energy() -> void:
	# Daylight makes lanterns nearly invisible; dusk/night gives a warm pool that
	# stays bright enough to read the path without flattening the scene.
	var energy := lerpf(2.6, 0.06, daylight)
	for light in _lights:
		light.light_energy = energy


func _exit_tree() -> void:
	for light in _lights:
		light.queue_free()
	_lights.clear()

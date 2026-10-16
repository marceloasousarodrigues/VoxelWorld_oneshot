class_name SaveManager
extends RefCounted

## Versioned JSON persistence for a VoxelWorld game.
##
## What is stored: the world seed, every block the player changed (or that the
## fluid simulation changed relative to the pristine generated world), the fluid
## overrides, and the player/inventory state.  Generated terrain is *not* stored:
## it is deterministic from the seed, so a save stays small no matter how far the
## player has explored.
##
## Recovery: a save whose header is missing, whose version is unknown or whose
## payload fails validation is never applied.  It is renamed to `*.corrupt-<n>`
## and reported, so a broken save can never destroy a working session.

const FORMAT := "voxelworld.godot.save"
## 1: block/fluid edits, player, inventory.  2: adds the day/night clock.  Version
## 1 saves still load: every newer field is optional and falls back to a default.
const VERSION := 2
const DEFAULT_DIRECTORY := "user://saves"
const DEFAULT_NAME := "world.json"

var directory := DEFAULT_DIRECTORY
var last_error := ""


func _init(save_directory: String = DEFAULT_DIRECTORY) -> void:
	directory = save_directory


func save_path() -> String:
	return directory.path_join(DEFAULT_NAME)


func ensure_directory() -> bool:
	if DirAccess.dir_exists_absolute(directory):
		return true
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		last_error = "could not create %s (error %d)" % [directory, error]
		return false
	return true


func to_dictionary(world: VoxelWorld, player: VoxelPlayer, inventory: Inventory, clock: DayNight = null) -> Dictionary:
	var block_edits: Array = []
	for position: Vector3i in world.edits:
		block_edits.append([position.x, position.y, position.z, int(world.edits[position])])
	block_edits.sort_custom(_compare_edit_rows)
	var fluid_edits: Array = []
	for position: Vector3i in world.fluid_overrides:
		fluid_edits.append([
			position.x, position.y, position.z,
			int(world.fluid_overrides[position]),
			1 if world.fluid_sources.has(position) else 0,
		])
	fluid_edits.sort_custom(_compare_edit_rows)
	var player_state := {}
	if player != null:
		player_state = {
			"position": [player.global_position.x, player.global_position.y, player.global_position.z],
			"yaw": player.rotation.y,
			"pitch": player.camera.rotation.x if player.camera != null else 0.0,
			"flying": player.flying,
		}
	return {
		"format": FORMAT,
		"version": VERSION,
		"engine": Engine.get_version_info().get("string", "unknown"),
		"seed": world.world_seed,
		"chunk_size": ChunkData.SIZE,
		"world_height": WorldGen.WORLD_HEIGHT,
		"stats": {
			"block_edits": block_edits.size(),
			"fluid_edits": fluid_edits.size(),
			"edits_generated": int(world.stats.get("edits", 0)),
		},
		"player": player_state,
		"inventory": inventory.to_dictionary() if inventory != null else {},
		"clock": clock.to_dictionary() if clock != null else {},
		"blocks": block_edits,
		"fluid": fluid_edits,
	}


func write(world: VoxelWorld, player: VoxelPlayer, inventory: Inventory, clock: DayNight = null) -> bool:
	last_error = ""
	if not ensure_directory():
		return false
	var payload := to_dictionary(world, player, inventory, clock)
	var path := save_path()
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		last_error = "could not open %s for writing (error %d)" % [temporary, FileAccess.get_open_error()]
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	# Write-then-rename so an interrupted save can never truncate the old one.
	var absolute_temporary := ProjectSettings.globalize_path(temporary)
	var absolute_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(absolute_path)
	var error := DirAccess.rename_absolute(absolute_temporary, absolute_path)
	if error != OK:
		last_error = "could not finalise %s (error %d)" % [path, error]
		return false
	return true


## Reads and validates a save without touching any live state.
## Returns `{"ok": bool, "error": String, "data": Dictionary}`.
func read() -> Dictionary:
	last_error = ""
	var path := save_path()
	if not FileAccess.file_exists(path):
		last_error = "no save at %s" % path
		return {"ok": false, "error": last_error}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_error = "could not open %s (error %d)" % [path, FileAccess.get_open_error()]
		return {"ok": false, "error": last_error}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_quarantine(path, "payload is not a JSON object")
		return {"ok": false, "error": last_error}
	var data: Dictionary = parsed
	if str(data.get("format", "")) != FORMAT:
		_quarantine(path, "unrecognised format header")
		return {"ok": false, "error": last_error}
	var version := int(data.get("version", -1))
	if version < 1 or version > VERSION:
		_quarantine(path, "unsupported save version %d" % version)
		return {"ok": false, "error": last_error}
	if int(data.get("chunk_size", -1)) != ChunkData.SIZE or int(data.get("world_height", -1)) != WorldGen.WORLD_HEIGHT:
		_quarantine(path, "world shape does not match this build")
		return {"ok": false, "error": last_error}
	var sanitised: Variant = _sanitise(data)
	if sanitised == null:
		_quarantine(path, last_error)
		return {"ok": false, "error": last_error}
	return {"ok": true, "error": "", "data": sanitised}


## Applies a validated save to the live world and player.  Returns a summary.
func apply(save: Dictionary, world: VoxelWorld, player: VoxelPlayer, inventory: Inventory, clock: DayNight = null) -> Dictionary:
	var data: Dictionary = save["data"]
	if int(data["seed"]) != world.world_seed:
		return {"ok": false, "error": "save belongs to seed %d, the world is seed %d" % [int(data["seed"]), world.world_seed]}
	var block_edits: Dictionary = {}
	for row: Array in data["blocks"]:
		block_edits[Vector3i(int(row[0]), int(row[1]), int(row[2]))] = int(row[3])
	var fluid_edits: Dictionary = {}
	var fluid_sources: Dictionary = {}
	for row: Array in data["fluid"]:
		var position := Vector3i(int(row[0]), int(row[1]), int(row[2]))
		fluid_edits[position] = int(row[3])
		if int(row[4]) == 1:
			fluid_sources[position] = true
	world.load_edits(block_edits, fluid_edits, fluid_sources)
	if clock != null and data.has("clock"):
		clock.from_dictionary(data["clock"] as Dictionary)
	if inventory != null and data.has("inventory") and not (data["inventory"] as Dictionary).is_empty():
		inventory.from_dictionary(data["inventory"])
	if player != null and not (data["player"] as Dictionary).is_empty():
		var state: Dictionary = data["player"]
		var position: Array = state["position"]
		player.teleport_to(Vector3(float(position[0]), float(position[1]), float(position[2])))
		player.look_yaw(rad_to_deg(float(state.get("yaw", 0.0))))
		player.look_pitch(rad_to_deg(float(state.get("pitch", 0.0))))
		if bool(state.get("flying", false)) and not player.flying:
			player.toggle_fly()
	return {"ok": true, "error": "", "block_edits": block_edits.size(), "fluid_edits": fluid_edits.size()}


# --- validation ----------------------------------------------------------

func _sanitise(data: Dictionary) -> Variant:
	var seed_value := int(data.get("seed", -1))
	if seed_value < 0:
		last_error = "save has no usable seed"
		return null
	var rows: Variant = _sanitise_rows(data.get("blocks"), 4)
	if rows == null:
		return null
	var fluid: Variant = _sanitise_rows(data.get("fluid"), 5)
	if fluid == null:
		return null
	var player_state: Variant = data.get("player", {})
	if typeof(player_state) != TYPE_DICTIONARY:
		last_error = "player state is not an object"
		return null
	if not (player_state as Dictionary).is_empty():
		var position: Variant = (player_state as Dictionary).get("position")
		if typeof(position) != TYPE_ARRAY or (position as Array).size() != 3:
			last_error = "player position is invalid"
			return null
	var inventory_state: Variant = data.get("inventory", {})
	if typeof(inventory_state) != TYPE_DICTIONARY:
		last_error = "inventory is not an object"
		return null
	var clock_state: Variant = data.get("clock", {})
	if typeof(clock_state) != TYPE_DICTIONARY:
		last_error = "the clock is not an object"
		return null
	return {
		"seed": seed_value,
		"player": player_state,
		"inventory": inventory_state,
		"clock": clock_state,
		"blocks": rows,
		"fluid": fluid,
		"version": int(data.get("version", 0)),
	}


func _sanitise_rows(candidate: Variant, width: int) -> Variant:
	if candidate == null:
		return []
	if typeof(candidate) != TYPE_ARRAY:
		last_error = "block or fluid table is not an array"
		return null
	var rows: Array = []
	for entry: Variant in (candidate as Array):
		if typeof(entry) != TYPE_ARRAY:
			last_error = "an edit row is not an array"
			return null
		var row: Array = entry
		if row.size() != width:
			last_error = "an edit row has %d columns, expected %d" % [row.size(), width]
			return null
		var cleaned: Array = []
		for value: Variant in row:
			if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
				last_error = "an edit row contains a non-numeric value"
				return null
			cleaned.append(int(value))
		rows.append(cleaned)
	return rows


func _compare_edit_rows(a: Array, b: Array) -> bool:
	for index in mini(a.size(), b.size()):
		if int(a[index]) == int(b[index]):
			continue
		return int(a[index]) < int(b[index])
	return a.size() < b.size()


func _quarantine(path: String, reason: String) -> void:
	last_error = "save rejected: %s" % reason
	var absolute := ProjectSettings.globalize_path(path)
	var suffix := 0
	while suffix < 100:
		var target := "%s.corrupt-%d" % [absolute, suffix]
		if not FileAccess.file_exists(target):
			break
		suffix += 1
	var moved := DirAccess.rename_absolute(absolute, "%s.corrupt-%d" % [absolute, suffix])
	if moved == OK:
		last_error += " (moved to %s)" % ("%s.corrupt-%d" % [path, suffix])
	else:
		last_error += " (could not quarantine the file)"


func delete_save() -> bool:
	var path := save_path()
	if not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK

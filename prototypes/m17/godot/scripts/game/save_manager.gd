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
## 1: block/fluid edits, player, inventory.  2: adds the day/night clock.
## 3: adds player health and breath.  4: adds hunger.  5: adds settlement stores
## and residents.  6: adds placed-station inventories (M19).  7: the inventory
## payload grows from one nine-slot row to 27 main slots + the nine-slot hotbar
## (M20).  8: adds wheat-crop growth progress (M21); the crop blocks themselves
## are ordinary block edits, so only the growth timers are new.  Older saves still
## load: every field a version did not know about is optional and keeps its
## default, and a nine-row inventory fills the hotbar while the 27 main slots
## start empty.
const VERSION := 8
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


func to_dictionary(world: VoxelWorld, player: VoxelPlayer, inventory: Inventory, clock: DayNight = null,
		health: Health = null, breath: float = -1.0, hunger: float = -1.0,
		npcs: Dictionary = {}, stations: Array = [], crops: Array = []) -> Dictionary:
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
		"health": health.to_dictionary() if health != null else {},
		"breath": breath,
		"hunger": hunger,
		"npcs": npcs,
		"stations": stations,
		"crops": crops,
		"blocks": block_edits,
		"fluid": fluid_edits,
	}


func write(world: VoxelWorld, player: VoxelPlayer, inventory: Inventory, clock: DayNight = null,
		health: Health = null, breath: float = -1.0, hunger: float = -1.0,
		npcs: Dictionary = {}, stations: Array = [], crops: Array = []) -> bool:
	last_error = ""
	if not ensure_directory():
		return false
	var payload := to_dictionary(world, player, inventory, clock, health, breath, hunger, npcs, stations, crops)
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
func apply(save: Dictionary, world: VoxelWorld, player: VoxelPlayer, inventory: Inventory, clock: DayNight = null,
		health: Health = null) -> Dictionary:
	if not save.get("ok", false) or typeof(save.get("data")) != TYPE_DICTIONARY:
		return {"ok": false, "error": "save is not validated"}
	var data: Dictionary = save["data"]
	if int(data["seed"]) != world.world_seed:
		return {"ok": false, "error": "save belongs to seed %d, the world is seed %d" % [int(data["seed"]), world.world_seed]}
	var health_data: Dictionary = data.get("health", {})
	if not health_data.is_empty() and not Health.new().from_dictionary(health_data):
		return {"ok": false, "error": "the saved health is invalid"}
	var breath := float(data.get("breath", -1.0))
	if int(data.get("version", 0)) >= 3 and (breath < 0.0 or breath > Survival.MAX_BREATH):
		return {"ok": false, "error": "the saved breath is invalid"}
	var hunger := float(data.get("hunger", -1.0))
	if int(data.get("version", 0)) >= 4 and (hunger < 0.0 or hunger > Survival.MAX_HUNGER):
		return {"ok": false, "error": "the saved hunger is invalid"}
	var npc_payload: Dictionary = data.get("npcs", {})
	if health != null and not health_data.is_empty():
		health.from_dictionary(health_data)
	var inventory_payload: Dictionary = data.get("inventory", {})
	if inventory != null and not inventory_payload.is_empty():
		# Probe on a scratch copy first: `Inventory.from_dictionary` is atomic for
		# the inventory itself, but this apply also mutates the world and the
		# player, so a bad payload must be rejected before any of that happens.
		if not Inventory.new().from_dictionary(inventory_payload):
			return {"ok": false, "error": "the saved inventory is invalid"}
	if player != null and not (data["player"] as Dictionary).is_empty():
		var player_state: Dictionary = data["player"]
		var saved_position: Array = player_state["position"]
		if saved_position.size() < 3:
			return {"ok": false, "error": "the saved player position is invalid"}
	var edits := data["blocks"] as Array
	var block_edits: Dictionary = {}
	for row: Array in edits:
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
	if inventory != null and not inventory_payload.is_empty():
		inventory.from_dictionary(inventory_payload)
	if player != null and not (data["player"] as Dictionary).is_empty():
		var state: Dictionary = data["player"]
		var position: Array = state["position"]
		player.teleport_to(Vector3(float(position[0]), float(position[1]), float(position[2])))
		player.look_yaw(rad_to_deg(float(state.get("yaw", 0.0))))
		player.look_pitch(rad_to_deg(float(state.get("pitch", 0.0))))
		if bool(state.get("flying", false)) and not player.flying:
			player.toggle_fly()
	return {"ok": true, "error": "", "block_edits": block_edits.size(), "fluid_edits": fluid_edits.size(),
		"breath": breath, "hunger": hunger, "npcs": npc_payload, "stations": data.get("stations", []),
		"crops": data.get("crops", [])}


# --- validation ----------------------------------------------------------

func _sanitise(data: Dictionary) -> Variant:
	var version := int(data.get("version", 0))
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
	if not (inventory_state as Dictionary).is_empty() \
			and not Inventory.new().from_dictionary(inventory_state as Dictionary):
		last_error = "the saved inventory is invalid"
		return null
	var clock_state: Variant = data.get("clock", {})
	if typeof(clock_state) != TYPE_DICTIONARY:
		last_error = "the clock is not an object"
		return null
	var health_state: Variant = data.get("health", {})
	if typeof(health_state) != TYPE_DICTIONARY:
		last_error = "health is not an object"
		return null
	if not (health_state as Dictionary).is_empty() and not Health.new().from_dictionary(health_state):
		last_error = "the saved health is invalid"
		return null
	var breath_value: Variant = data.get("breath", -1.0)
	if typeof(breath_value) != TYPE_FLOAT and typeof(breath_value) != TYPE_INT:
		last_error = "breath is not a number"
		return null
	if version >= 3 and (float(breath_value) < 0.0 or float(breath_value) > Survival.MAX_BREATH):
		last_error = "breath is outside the valid range"
		return null
	var hunger_value: Variant = data.get("hunger", -1.0)
	if typeof(hunger_value) != TYPE_FLOAT and typeof(hunger_value) != TYPE_INT:
		last_error = "hunger is not a number"
		return null
	if version >= 4 and (float(hunger_value) < 0.0 or float(hunger_value) > Survival.MAX_HUNGER):
		last_error = "hunger is outside the valid range"
		return null
	var npcs_state: Variant = data.get("npcs", {})
	if typeof(npcs_state) != TYPE_DICTIONARY:
		last_error = "npcs is not an object"
		return null
	var stations_state: Variant = data.get("stations", [])
	if typeof(stations_state) != TYPE_ARRAY:
		last_error = "stations is not an array"
		return null
	var crops_state: Variant = data.get("crops", [])
	if typeof(crops_state) != TYPE_ARRAY:
		last_error = "crops is not an array"
		return null
	for entry: Variant in (crops_state as Array):
		if typeof(entry) != TYPE_ARRAY or (entry as Array).size() != 4:
			last_error = "a crop row is malformed"
			return null
		for value: Variant in (entry as Array):
			if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
				last_error = "a crop row contains a non-numeric value"
				return null
		var elapsed := float((entry as Array)[3])
		if elapsed < 0.0 or elapsed > Farming.STAGE_SECONDS:
			last_error = "a crop row has an invalid growth time"
			return null
	return {
		"seed": seed_value,
		"player": player_state,
		"inventory": inventory_state,
		"clock": clock_state,
		"health": health_state,
		"breath": float(breath_value),
		"hunger": float(hunger_value),
		"npcs": npcs_state,
		"stations": stations_state,
		"crops": crops_state,
		"blocks": rows,
		"fluid": fluid,
		"version": version,
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

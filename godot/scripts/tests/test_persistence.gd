extends RefCounted

## Persistence (`SaveManager`): the write -> read -> apply round-trip, the
## validation rules and the corrupt-save quarantine.  This is the runtime
## reliability path that was previously only exercised indirectly: the clock
## payload had a round-trip test, but nothing ever constructed a `SaveManager`,
## wrote a world to disk and loaded it back.
##
## The test uses its own directory under `user://` so it cannot touch the real
## save, and removes every file it created before returning.  The players are
## parented to the scene tree because a detached `Node3D` has no global
## transform (Godot returns identity and errors otherwise).


const TEST_DIRECTORY := "user://m17_persistence_test"


func name() -> String:
	return "persistence"


## Deletes every file the test wrote and the directory itself, so a passing run
## leaves nothing behind and a rerun starts clean.
func _clean() -> void:
	var directory := DirAccess.open(TEST_DIRECTORY)
	if directory == null:
		return
	for file_name: String in directory.get_files():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_DIRECTORY.path_join(file_name)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_DIRECTORY))


func _write_raw(saves: SaveManager, text: String) -> void:
	saves.ensure_directory()
	var file := FileAccess.open(saves.save_path(), FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _set_legacy_version(payload: Dictionary, version: int) -> void:
	payload["version"] = version
	for row: Array in payload.get("blocks", []):
		row.resize(4)


func _files_matching(prefix: String) -> Array[String]:
	var matches: Array[String] = []
	var directory := DirAccess.open(TEST_DIRECTORY)
	if directory == null:
		return matches
	for file_name: String in directory.get_files():
		if file_name.begins_with(prefix):
			matches.append(file_name)
	return matches


func _has_file(file_name: String) -> bool:
	var directory := DirAccess.open(TEST_DIRECTORY)
	if directory == null:
		return false
	return directory.get_files().has(file_name)


## A player that is actually in the scene tree, so `global_position` is real.
func _spawn_player(world: VoxelWorld) -> VoxelPlayer:
	var player := VoxelPlayer.new()
	player.world = world
	player.set_process(false)
	player.set_physics_process(false)
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(player)
	return player


func _release_player(player: VoxelPlayer) -> void:
	if player == null:
		return
	var parent := player.get_parent()
	if parent != null:
		parent.remove_child(player)
	player.free()


func run(h: TestHarness) -> void:
	_clean()
	var saves := SaveManager.new(TEST_DIRECTORY)

	# --- build a live world worth saving -----------------------------------
	var world := VoxelWorld.new(17017)
	var chunk_coord := Vector3i(0, 3, 0)
	world.ensure_chunk(chunk_coord)
	var edited := Vector3i(8, 60, 8)
	var removed := Vector3i(9, 60, 8)
	var built := Vector3i(10, 60, 8)
	var stair := Vector3i(11, 60, 8)
	h.check(world.set_block(edited, BlockDB.PLANKS), "a block is placed before saving")
	h.check(world.set_block(removed, BlockDB.AIR), "a block is broken before saving")
	h.check(world.set_block(built, BlockDB.TIMBER_FRAME), "an M22 building block is placed before saving")
	h.check(world.set_block_state(stair, BlockDB.STAIR, 6), "an oriented stair is placed before saving")
	var fluid_cell := Vector3i(8, 60, 9)
	world.fluid_overrides[fluid_cell] = 7
	world.fluid_sources[fluid_cell] = true

	var player := _spawn_player(world)
	player.teleport_to(Vector3(10.5, 72.0, -3.5))
	player.look_yaw(45.0)
	player.look_pitch(-15.0)
	player.flying = true

	var inventory := Inventory.new()
	inventory.add(BlockDB.STONE, 5)
	inventory.add(BlockDB.PLANKS, 2)
	# Put a stack in a storage row, not just the hotbar: M20's 27 main slots must
	# survive the same save/load path as the hotbar.
	inventory.put_stack(Inventory.MAIN_FIRST + 4, {"item": ItemDB.IRON_LUMP, "count": 7})

	var clock := DayNight.new(0.42, 900.0)

	var health := Health.new(20.0, 13.0)
	var breath := 4.5
	var hunger := 11.0

	# --- write --------------------------------------------------------------
	h.check(saves.write(world, player, inventory, clock, health, breath, hunger), "write() reports success")
	h.check(FileAccess.file_exists(saves.save_path()), "the save file exists on disk")

	# --- read + validate ----------------------------------------------------
	var result: Dictionary = saves.read()
	h.check(bool(result["ok"]), "read() accepts the save it just wrote (%s)" % str(result.get("error", "")))
	var data: Dictionary = result["data"]
	h.eq(int(data["seed"]), 17017, "the saved seed round-trips")
	h.eq(int(data["version"]), SaveManager.VERSION, "the save is written at the current version")
	h.eq(int(SaveManager.VERSION), 9, "the current save version is 9")
	h.eq(int(data["terrain_generator_version"]), WorldGen.CURRENT_VERSION,
		"new saves record the current terrain generator version")
	var saved_stair_row: Array = []
	for row: Array in data["blocks"]:
		if int(row[3]) == BlockDB.STAIR:
			saved_stair_row = row
			break
	h.eq(saved_stair_row.size(), 5, "a v9 block edit row stores orientation in its fifth value")
	if saved_stair_row.size() == 5:
		h.eq(int(saved_stair_row[4]), 6, "the v9 row stores the stair orientation")

	# --- apply to a fresh session ------------------------------------------
	var restored_world := VoxelWorld.new(17017)
	restored_world.ensure_chunk(chunk_coord)
	var restored_player := _spawn_player(restored_world)
	var restored_inventory := Inventory.new()
	var restored_clock := DayNight.new(0.0, 900.0)
	var restored_health := Health.new()
	var applied: Dictionary = saves.apply(result, restored_world, restored_player, restored_inventory, restored_clock, restored_health)
	h.check(bool(applied["ok"]), "apply() accepts a save from the same seed")
	h.eq(int(applied["block_edits"]), 4, "apply() reports the four block edits")
	h.eq(int(applied["fluid_edits"]), 1, "apply() reports the one fluid edit")
	h.approx(restored_health.health, 13.0, 1e-6, "the saved health survived the round-trip")
	h.approx(restored_health.max_health, 20.0, 1e-6, "the saved maximum health survived the round-trip")
	h.approx(float(applied["breath"]), 4.5, 1e-6, "the saved breath survived the round-trip")
	h.approx(float(applied["hunger"]), 11.0, 1e-6, "the saved hunger survived the round-trip")

	h.eq(restored_world.get_block(edited), BlockDB.PLANKS, "the placed block survived the round-trip")
	h.eq(restored_world.get_block(built), BlockDB.TIMBER_FRAME, "the M22 building block survived the round-trip")
	h.eq(restored_world.get_block(stair), BlockDB.STAIR, "the stair survived the round-trip")
	h.eq(restored_world.get_orientation(stair), 6, "the stair orientation survived the round-trip")
	h.eq(restored_world.get_block(removed), BlockDB.AIR, "the broken block stayed broken")
	h.check(restored_world.edits.has(edited), "the restored world records the edit")
	h.eq(int(restored_world.fluid_overrides.get(fluid_cell, -1)), 7, "the fluid override survived")
	h.check(restored_world.fluid_sources.has(fluid_cell), "the fluid source flag survived")
	h.eq(restored_world.generator.terrain_version, WorldGen.CURRENT_VERSION,
		"a current save restores its terrain generator version")

	# M29 saves have the same v9 save schema but no terrain generator metadata.
	# This fixture is synthesized from the real M29 SaveManager payload shape;
	# it proves missing-field handling and edit preservation, not every historical
	# save file ever produced by earlier generator revisions.
	var legacy_payload: Dictionary = saves.to_dictionary(world, player, inventory, clock,
		health, breath, hunger)
	legacy_payload.erase("terrain_generator_version")
	_write_raw(saves, JSON.stringify(legacy_payload))
	var legacy_terrain_result: Dictionary = saves.read()
	h.check(bool(legacy_terrain_result["ok"]), "a v9 M29 fixture without terrain metadata remains readable")
	if bool(legacy_terrain_result["ok"]):
		var legacy_applied := saves.apply(legacy_terrain_result, restored_world, restored_player,
			restored_inventory, null, null)
		h.check(bool(legacy_applied["ok"]), "a metadata-free save applies using the legacy policy")
		h.eq(restored_world.generator.terrain_version, WorldGen.LEGACY_VERSION,
			"a metadata-free save selects the M29 terrain generator")
		var legacy_reference := VoxelWorld.new(17017, WorldGen.LEGACY_VERSION)
		legacy_reference.ensure_chunk(chunk_coord)
		legacy_reference.load_edits(restored_world.edits, restored_world.fluid_overrides,
			restored_world.fluid_sources, restored_world.edit_orientations)
		h.eq(restored_world.chunks[chunk_coord].blocks,
			legacy_reference.chunks[chunk_coord].blocks,
			"untouched legacy terrain and edits match the M29 generator output")
		h.eq(restored_world.get_block(edited), BlockDB.PLANKS,
			"legacy block placement survives generator migration")
		h.eq(restored_world.get_block(removed), BlockDB.AIR,
			"legacy block removal survives generator migration")
		var migrated_payload: Dictionary = saves.to_dictionary(restored_world, restored_player,
			restored_inventory, clock, health, breath, hunger)
		h.eq(int(migrated_payload["terrain_generator_version"]), WorldGen.LEGACY_VERSION,
			"saving a legacy world keeps its generator version")
		_write_raw(saves, JSON.stringify(migrated_payload))
		var migrated_result := saves.read()
		h.check(bool(migrated_result["ok"]),
			"a migrated legacy save can be read again (%s)" % str(migrated_result.get("error", "")))
		if bool(migrated_result["ok"]):
			var migrated_world := VoxelWorld.new(17017)
			migrated_world.ensure_chunk(chunk_coord)
			var migrated_apply := saves.apply(migrated_result, migrated_world, null, Inventory.new())
			h.check(bool(migrated_apply["ok"]), "a migrated legacy save applies to a fresh world")
			h.eq(migrated_world.generator.terrain_version, WorldGen.LEGACY_VERSION,
				"the migrated save retains the legacy generator on reload")
			h.eq(migrated_world.get_block(edited), BlockDB.PLANKS,
				"the placed player edit survives migration and reload")
			h.eq(migrated_world.get_block(removed), BlockDB.AIR,
				"the removed player block survives migration and reload")

	var unsupported_terrain: Dictionary = saves.to_dictionary(world, player, inventory)
	unsupported_terrain["terrain_generator_version"] = 99
	_write_raw(saves, JSON.stringify(unsupported_terrain))
	var unsupported_terrain_result := saves.read()
	h.check(not bool(unsupported_terrain_result["ok"]),
		"an unsupported terrain generator version is rejected explicitly")
	h.check(not FileAccess.file_exists(saves.save_path()),
		"an unsupported terrain version is quarantined")
	var malformed_terrain: Dictionary = saves.to_dictionary(world, player, inventory)
	malformed_terrain["terrain_generator_version"] = "1"
	_write_raw(saves, JSON.stringify(malformed_terrain))
	var malformed_terrain_result := saves.read()
	h.check(not bool(malformed_terrain_result["ok"]),
		"a non-integer terrain generator version is rejected explicitly")
	h.check(not FileAccess.file_exists(saves.save_path()),
		"malformed terrain metadata is quarantined")

	h.approx(restored_player.global_position.x, 10.5, 1e-3, "the player x position survived")
	h.approx(restored_player.global_position.y, 72.0, 1e-3, "the player y position survived")
	h.approx(restored_player.global_position.z, -3.5, 1e-3, "the player z position survived")
	h.approx(restored_player.look_angles().x, 45.0, 1e-2, "the player yaw survived")
	h.approx(restored_player.look_angles().y, -15.0, 1e-2, "the player pitch survived")
	h.check(restored_player.flying, "the flying flag survived")

	h.eq(restored_inventory.count_of(BlockDB.STONE), 5, "the inventory stone count survived")
	h.eq(restored_inventory.count_of(BlockDB.PLANKS), 2, "the inventory planks count survived")
	h.eq(restored_inventory.count_of(ItemDB.IRON_LUMP), 7, "a storage-row item survived the round-trip")
	h.eq(restored_inventory.slots[Inventory.MAIN_FIRST + 4], ItemDB.IRON_LUMP,
		"the storage-row slot index survived")
	h.approx(restored_clock.time_of_day, 0.42, 1e-6, "the clock time survived")
	h.approx(restored_clock.day_length_seconds, 900.0, 1e-6, "the clock day length survived")

	# A v8 row has no orientation field; it is normalized to orientation zero.
	# Build a real v9 write payload (with the format/world-shape headers a save
	# file needs), then downgrade it to the v8 four-column block row.
	var legacy_v8: Dictionary = saves.to_dictionary(world, player, inventory, clock, health, breath, hunger)
	_set_legacy_version(legacy_v8, 8)
	_write_raw(saves, JSON.stringify(legacy_v8))
	var legacy_result: Dictionary = saves.read()
	h.check(bool(legacy_result["ok"]), "a v8 four-value block row remains loadable")
	if bool(legacy_result["ok"]):
		var legacy_world := VoxelWorld.new(17017)
		legacy_world.ensure_chunk(chunk_coord)
		var legacy_applied: Dictionary = saves.apply(legacy_result, legacy_world, null, null)
		h.check(bool(legacy_applied["ok"]), "a v8 save applies to the world")
		h.eq(legacy_world.get_block(stair), BlockDB.STAIR, "the legacy stair block id is retained")
		h.eq(legacy_world.get_orientation(stair), 0, "a v8 row defaults orientation to zero")

	# --- a save from another seed must never be applied --------------------
	var other_world := VoxelWorld.new(4242)
	var rejected: Dictionary = saves.apply(result, other_world, player, inventory, clock)
	h.check(not bool(rejected["ok"]), "apply() refuses a save from a different seed")
	h.check(not other_world.edits.has(edited), "a refused save leaves the world untouched")

	# --- version 1 and 2 saves still load (newer fields are optional) -------
	var v1_payload: Dictionary = saves.to_dictionary(world, player, inventory, clock, health, breath)
	_set_legacy_version(v1_payload, 1)
	v1_payload.erase("clock")
	v1_payload.erase("health")
	v1_payload.erase("breath")
	_write_raw(saves, JSON.stringify(v1_payload))
	var v1_result: Dictionary = saves.read()
	h.check(bool(v1_result["ok"]), "a version 1 save is accepted")
	if bool(v1_result["ok"]):
		var clock_before := DayNight.new(0.66, 900.0)
		var health_before := Health.new(20.0, 9.0)
		var v1_applied: Dictionary = saves.apply(v1_result, restored_world, restored_player, restored_inventory, clock_before, health_before)
		h.check(bool(v1_applied["ok"]), "a version 1 save applies")
		h.approx(clock_before.time_of_day, 0.66, 1e-6, "a version 1 save leaves the clock untouched")
		h.approx(health_before.health, 9.0, 1e-6, "a version 1 save leaves health untouched")
		h.less(float(v1_applied["breath"]), 0.0, "a version 1 save reports no breath")
		h.less(float(v1_applied["hunger"]), 0.0, "a version 1 save reports no hunger")

	var v2_payload: Dictionary = saves.to_dictionary(world, player, inventory, clock, health, breath)
	_set_legacy_version(v2_payload, 2)
	v2_payload.erase("health")
	v2_payload.erase("breath")
	v2_payload.erase("hunger")
	_write_raw(saves, JSON.stringify(v2_payload))
	var v2_result: Dictionary = saves.read()
	h.check(bool(v2_result["ok"]), "a version 2 save is accepted")
	if bool(v2_result["ok"]):
		var v2_clock := DayNight.new(0.0, 900.0)
		var v2_health := Health.new(20.0, 20.0)
		var v2_applied: Dictionary = saves.apply(v2_result, restored_world, restored_player, restored_inventory, v2_clock, v2_health)
		h.approx(v2_clock.time_of_day, 0.42, 1e-6, "a version 2 save still restores the clock")
		h.approx(v2_health.health, 20.0, 1e-6, "a version 2 save leaves health untouched")
		h.less(float(v2_applied["hunger"]), 0.0, "a version 2 save reports no hunger")

	# A version 3 save has breath but no hunger: it loads, and the game keeps a
	# full hunger bar (the sentinel tells the game to leave it alone).
	var v3_payload: Dictionary = saves.to_dictionary(world, player, inventory, clock, health, breath)
	_set_legacy_version(v3_payload, 3)
	v3_payload.erase("hunger")
	v3_payload.erase("npcs")
	v3_payload.erase("stations")
	_write_raw(saves, JSON.stringify(v3_payload))
	var v3_result: Dictionary = saves.read()
	h.check(bool(v3_result["ok"]), "a version 3 save is accepted")
	if bool(v3_result["ok"]):
		var v3_applied: Dictionary = saves.apply(v3_result, restored_world, restored_player, restored_inventory, null, null)
		h.approx(float(v3_applied["breath"]), 4.5, 1e-6, "a version 3 save still restores breath")
		h.less(float(v3_applied["hunger"]), 0.0, "a version 3 save reports no hunger")
		h.eq((v3_applied["npcs"] as Dictionary).size(), 0, "a version 3 save carries no residents")
		h.eq((v3_applied["stations"] as Array).size(), 0, "a version 3 save carries no station state")

	# A version 7 save has no crop payload: it still loads and starts with no
	# tracked crops, so the M20 save format remains readable.
	var v7_payload: Dictionary = saves.to_dictionary(world, player, inventory, clock, health, breath, hunger)
	_set_legacy_version(v7_payload, 7)
	v7_payload.erase("crops")
	_write_raw(saves, JSON.stringify(v7_payload))
	var v7_result: Dictionary = saves.read()
	h.check(bool(v7_result["ok"]), "a version 7 save is still accepted")
	if bool(v7_result["ok"]):
		var v7_applied: Dictionary = saves.apply(v7_result, restored_world, restored_player,
			restored_inventory, null, null)
		h.check(bool(v7_applied["ok"]), "a version 7 save applies")
		h.eq((v7_applied["crops"] as Array).size(), 0, "a version 7 save carries no crop progress")

	# A current-version save round-trips the settlement stores and residents.
	var npc_payload := {
		"settlements": [{"id": "settlement-8-8", "name": "Oakhollow", "store": [[BlockDB.OAK_LOG, 6]]}],
		"npcs": [{
			"id": "settlement-8-8:npc0", "settlement": "settlement-8-8", "name": "Bram",
			"role": 0, "position": [9.0, 70.0, 9.0], "home": [8.5, 70.0, 8.5],
			"carried": [[ItemDB.STICK, 2]], "health": 12.0, "alive": true,
			"gathered": 3, "delivered": 1,
		}],
	}
	var npc_written := saves.to_dictionary(world, player, inventory, clock, health, breath, hunger, npc_payload)
	_write_raw(saves, JSON.stringify(npc_written))
	var npc_result: Dictionary = saves.read()
	h.check(bool(npc_result["ok"]), "a save with residents is accepted")
	if bool(npc_result["ok"]):
		var npc_applied: Dictionary = saves.apply(npc_result, restored_world, restored_player,
			restored_inventory, null, null)
		h.check(bool(npc_applied["ok"]), "a save with residents applies")
		var restored_npcs: Dictionary = npc_applied["npcs"]
		h.eq((restored_npcs.get("npcs", []) as Array).size(), 1, "the resident survived the round-trip")
		h.eq((restored_npcs.get("settlements", []) as Array).size(), 1, "the settlement store survived")

	# A malformed npcs payload is rejected and quarantined.
	var bad_npcs: Dictionary = saves.to_dictionary(world, player, inventory, clock, health, breath, hunger)
	bad_npcs["npcs"] = "not an object"
	_write_raw(saves, JSON.stringify(bad_npcs))
	h.check(not bool(saves.read()["ok"]), "a malformed residents payload is rejected")
	h.check(not FileAccess.file_exists(saves.save_path()), "the malformed-residents save is quarantined")

	# A current-version save round-trips placed-station inventories and timers.
	var saved_station := Station.new(Station.FURNACE)
	saved_station.inventory.insert(Station.FURNACE_INPUT_SLOT, {"item": BlockDB.SAND, "count": 2})
	saved_station.inventory.insert(Station.FURNACE_FUEL_SLOT, {"item": ItemDB.COAL, "count": 1})
	saved_station.inventory.insert(Station.FURNACE_OUTPUT_SLOT, {"item": BlockDB.GLASS, "count": 1}, true)
	saved_station.step(1.5)
	var station_rows: Array = [[8, 70, 8, saved_station.to_dictionary()]]
	var station_written: Dictionary = saves.to_dictionary(world, player, inventory, clock, health, breath,
		hunger, npc_payload, station_rows)
	_write_raw(saves, JSON.stringify(station_written))
	var station_result: Dictionary = saves.read()
	h.check(bool(station_result["ok"]), "a save with station state is accepted")
	if bool(station_result["ok"]):
		var station_applied: Dictionary = saves.apply(station_result, restored_world, restored_player,
			restored_inventory, null, null)
		h.check(bool(station_applied["ok"]), "a save with station state applies")
		var restored_rows: Array = station_applied["stations"]
		h.eq(restored_rows.size(), 1, "the station row survived the round-trip")
		var registry := StationRegistry.new(restored_world)
		var station_summary: Dictionary = registry.from_dictionary(restored_rows)
		h.eq(int(station_summary["accepted"]), 1, "the station payload restores into the registry")
		var restored_station = registry.peek(Vector3i(8, 70, 8))
		h.check(restored_station != null, "the restored station is keyed by its world position")
		if restored_station != null:
			h.eq(restored_station.inventory.total_of(BlockDB.SAND), 2, "the station input survived")
			h.eq(restored_station.inventory.total_of(BlockDB.GLASS), 1, "the station output survived")
			h.approx(restored_station.cook_progress, saved_station.cook_progress, 1e-6,
				"the furnace cook progress survived")

	# A current-version save round-trips wheat-crop growth progress.
	var crop_rows: Array = [[8, 71, 8, 12.5]]
	var crop_written: Dictionary = saves.to_dictionary(world, player, inventory, clock, health, breath,
		hunger, npc_payload, station_rows, crop_rows)
	_write_raw(saves, JSON.stringify(crop_written))
	var crop_result: Dictionary = saves.read()
	h.check(bool(crop_result["ok"]), "a save with crop progress is accepted")
	if bool(crop_result["ok"]):
		var crop_applied: Dictionary = saves.apply(crop_result, restored_world, restored_player,
			restored_inventory, null, null)
		h.check(bool(crop_applied["ok"]), "a save with crop progress applies")
		var farming := Farming.new(17017)
		var crop_summary: Dictionary = farming.from_dictionary(crop_applied["crops"])
		h.eq(int(crop_summary["accepted"]), 1, "the crop growth timer survived the round-trip")
		h.approx(farming.progress.get(Vector3i(8, 71, 8), -1.0), 12.5, 1e-6,
			"the restored crop resumes at its saved growth time")

	# A crop row outside a stage's growth window is rejected.
	var bad_crops: Dictionary = crop_written.duplicate(true)
	bad_crops["crops"] = [[8, 71, 8, 9999.0]]
	_write_raw(saves, JSON.stringify(bad_crops))
	h.check(not bool(saves.read()["ok"]), "an invalid crop growth timer is rejected")
	h.check(not FileAccess.file_exists(saves.save_path()), "the malformed-crop save is quarantined")

	# A malformed stations payload is rejected and quarantined.
	var bad_stations: Dictionary = saves.to_dictionary(world, player, inventory, clock, health, breath, hunger,
		npc_payload, station_rows)
	bad_stations["stations"] = "not an array"
	_write_raw(saves, JSON.stringify(bad_stations))
	h.check(not bool(saves.read()["ok"]), "a malformed stations payload is rejected")
	h.check(not FileAccess.file_exists(saves.save_path()), "the malformed-stations save is quarantined")

	# --- a save whose health payload is malformed is quarantined ------------
	var bad_health: Dictionary = saves.to_dictionary(world, player, inventory, clock, health, breath)
	bad_health["health"] = "broken"
	_write_raw(saves, JSON.stringify(bad_health))
	var bad_result: Dictionary = saves.read()
	h.check(not bool(bad_result["ok"]), "a save with a malformed health payload is rejected")
	h.check(not FileAccess.file_exists(saves.save_path()), "the malformed-health save is removed from its path")

	# Current-version breath is required to be within the survival range.
	for invalid_breath: float in [-1.0, Survival.MAX_BREATH + 1.0]:
		var bad_breath: Dictionary = saves.to_dictionary(world, player, inventory, clock, health, breath)
		bad_breath["breath"] = invalid_breath
		_write_raw(saves, JSON.stringify(bad_breath))
		var bad_breath_result: Dictionary = saves.read()
		h.check(not bool(bad_breath_result["ok"]), "out-of-range v3 breath is rejected: %s" % invalid_breath)
		h.check(not FileAccess.file_exists(saves.save_path()), "invalid-breath v3 save is quarantined")

	# Current-version hunger is required to be within its range too.
	for invalid_hunger: float in [-1.0, Survival.MAX_HUNGER + 1.0]:
		var bad_hunger: Dictionary = saves.to_dictionary(world, player, inventory, clock, health, breath, hunger)
		bad_hunger["hunger"] = invalid_hunger
		_write_raw(saves, JSON.stringify(bad_hunger))
		var bad_hunger_result: Dictionary = saves.read()
		h.check(not bool(bad_hunger_result["ok"]), "out-of-range v4 hunger is rejected: %s" % invalid_hunger)
		h.check(not FileAccess.file_exists(saves.save_path()), "invalid-hunger v4 save is quarantined")

	# A malformed inventory payload is quarantined and never applied.
	var bad_inventory: Dictionary = saves.to_dictionary(world, player, inventory, clock, health, breath, hunger)
	bad_inventory["inventory"] = {"hotbar": [[ItemDB.COUNT + 3, 1]], "selected": 0}
	_write_raw(saves, JSON.stringify(bad_inventory))
	var bad_inventory_result: Dictionary = saves.read()
	h.check(not bool(bad_inventory_result["ok"]), "a save with an invalid item id is rejected")
	h.check(not FileAccess.file_exists(saves.save_path()), "the invalid-inventory save is quarantined")

	# Rejected data must be validated before any live state changes.
	var protected_world := VoxelWorld.new(17017)
	protected_world.ensure_chunk(chunk_coord)
	var protected_player := _spawn_player(protected_world)
	protected_player.teleport_to(Vector3(1.5, 70.0, 1.5))
	var protected_inventory := Inventory.new()
	protected_inventory.add(BlockDB.DIRT, 3)
	var protected_health := Health.new(20.0, 8.0)
	var protected_position := protected_player.global_position
	var protected_items := protected_inventory.to_dictionary()
	var bad_apply: Dictionary = result.duplicate(true)
	(bad_apply["data"] as Dictionary)["breath"] = -2.0
	var invalid_apply := saves.apply(bad_apply, protected_world, protected_player, protected_inventory, null, protected_health)
	h.check(not bool(invalid_apply["ok"]), "invalid save cannot be applied")
	h.check(protected_world.edits.is_empty(), "invalid save leaves world edits untouched")
	h.approx(protected_health.health, 8.0, 1e-6, "invalid save leaves health untouched")
	h.eq(protected_inventory.to_dictionary(), protected_items, "invalid save leaves inventory untouched")
	h.approx(protected_player.global_position.distance_to(protected_position), 0.0, 1e-6, "invalid save leaves player untouched")
	_release_player(protected_player)

	# --- quarantine paths ---------------------------------------------------
	# (a) an unknown version is rejected and the file is moved aside.
	var v9_payload: Dictionary = saves.to_dictionary(world, player, inventory, clock)
	v9_payload["version"] = 99
	_write_raw(saves, JSON.stringify(v9_payload))
	var v9_result: Dictionary = saves.read()
	h.check(not bool(v9_result["ok"]), "an unknown save version is rejected")
	h.check(not FileAccess.file_exists(saves.save_path()), "the rejected save is removed from its path")
	h.greater(float(_files_matching("world.json.corrupt-").size()), 0.0, "the rejected save is quarantined, not lost")

	# (b) valid JSON that is not a save object is rejected and quarantined too.
	#     (A malformed file would make the engine itself log a JSON error; an
	#     array exercises the same `payload is not a JSON object` branch quietly.)
	_write_raw(saves, "[]\n")
	var garbage_result: Dictionary = saves.read()
	h.check(not bool(garbage_result["ok"]), "a non-object save is rejected")
	h.check(garbage_result["error"] != "", "the rejection carries a reason")
	h.check(not FileAccess.file_exists(saves.save_path()), "the rejected payload is removed from its path")

	# (c) a missing save is reported, not crashed on.
	saves.delete_save()
	var missing: Dictionary = saves.read()
	h.check(not bool(missing["ok"]), "reading a missing save is a clean failure")
	h.check(not _has_file("world.json"), "no active save file is left behind")

	# --- leave nothing behind ----------------------------------------------
	_release_player(player)
	_release_player(restored_player)
	_clean()
	h.eq(_files_matching("").size(), 0, "the test cleaned up every file it wrote")

	h.finish()

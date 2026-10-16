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
	h.check(world.set_block(edited, BlockDB.PLANKS), "a block is placed before saving")
	h.check(world.set_block(removed, BlockDB.AIR), "a block is broken before saving")
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

	var clock := DayNight.new(0.42, 900.0)

	# --- write --------------------------------------------------------------
	h.check(saves.write(world, player, inventory, clock), "write() reports success")
	h.check(FileAccess.file_exists(saves.save_path()), "the save file exists on disk")

	# --- read + validate ----------------------------------------------------
	var result: Dictionary = saves.read()
	h.check(bool(result["ok"]), "read() accepts the save it just wrote")
	var data: Dictionary = result["data"]
	h.eq(int(data["seed"]), 17017, "the saved seed round-trips")

	# --- apply to a fresh session ------------------------------------------
	var restored_world := VoxelWorld.new(17017)
	restored_world.ensure_chunk(chunk_coord)
	var restored_player := _spawn_player(restored_world)
	var restored_inventory := Inventory.new()
	var restored_clock := DayNight.new(0.0, 900.0)
	var applied: Dictionary = saves.apply(result, restored_world, restored_player, restored_inventory, restored_clock)
	h.check(bool(applied["ok"]), "apply() accepts a save from the same seed")
	h.eq(int(applied["block_edits"]), 2, "apply() reports the two block edits")
	h.eq(int(applied["fluid_edits"]), 1, "apply() reports the one fluid edit")

	h.eq(restored_world.get_block(edited), BlockDB.PLANKS, "the placed block survived the round-trip")
	h.eq(restored_world.get_block(removed), BlockDB.AIR, "the broken block stayed broken")
	h.check(restored_world.edits.has(edited), "the restored world records the edit")
	h.eq(int(restored_world.fluid_overrides.get(fluid_cell, -1)), 7, "the fluid override survived")
	h.check(restored_world.fluid_sources.has(fluid_cell), "the fluid source flag survived")

	h.approx(restored_player.global_position.x, 10.5, 1e-3, "the player x position survived")
	h.approx(restored_player.global_position.y, 72.0, 1e-3, "the player y position survived")
	h.approx(restored_player.global_position.z, -3.5, 1e-3, "the player z position survived")
	h.approx(restored_player.look_angles().x, 45.0, 1e-2, "the player yaw survived")
	h.approx(restored_player.look_angles().y, -15.0, 1e-2, "the player pitch survived")
	h.check(restored_player.flying, "the flying flag survived")

	h.eq(restored_inventory.count_of(BlockDB.STONE), 5, "the inventory stone count survived")
	h.eq(restored_inventory.count_of(BlockDB.PLANKS), 2, "the inventory planks count survived")
	h.approx(restored_clock.time_of_day, 0.42, 1e-6, "the clock time survived")
	h.approx(restored_clock.day_length_seconds, 900.0, 1e-6, "the clock day length survived")

	# --- a save from another seed must never be applied --------------------
	var other_world := VoxelWorld.new(4242)
	var rejected: Dictionary = saves.apply(result, other_world, player, inventory, clock)
	h.check(not bool(rejected["ok"]), "apply() refuses a save from a different seed")
	h.check(not other_world.edits.has(edited), "a refused save leaves the world untouched")

	# --- version 1 saves still load (the clock field is optional) -----------
	var v1_payload: Dictionary = saves.to_dictionary(world, player, inventory, clock)
	v1_payload["version"] = 1
	v1_payload.erase("clock")
	_write_raw(saves, JSON.stringify(v1_payload))
	var v1_result: Dictionary = saves.read()
	h.check(bool(v1_result["ok"]), "a version 1 save is accepted")
	if bool(v1_result["ok"]):
		var clock_before := DayNight.new(0.66, 900.0)
		saves.apply(v1_result, restored_world, restored_player, restored_inventory, clock_before)
		h.approx(clock_before.time_of_day, 0.66, 1e-6, "a version 1 save leaves the clock untouched")

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

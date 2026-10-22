extends RefCounted

## M26 protection: a player-built world must survive saving, unloading,
## restarting and reopening, and a broken or interrupted save must never replace
## a good one.
##
## The build below deliberately straddles a chunk boundary and mixes ordinary
## blocks, a removed block, oriented stairs, a station block and a door.  It is
## written to disk, applied to a fresh world, unloaded/regenerated, cleared and
## re-applied, and finally read again from disk to simulate a restart.


const TEST_DIRECTORY := "user://m26_protection_test"


func name() -> String:
	return "M26 save and stream protection"


func _clean() -> void:
	var directory := DirAccess.open(TEST_DIRECTORY)
	if directory == null:
		return
	for file_name: String in directory.get_files():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_DIRECTORY.path_join(file_name)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_DIRECTORY))


func _spawn_player(world: VoxelWorld) -> VoxelPlayer:
	var player := VoxelPlayer.new()
	player.world = world
	player.set_process(false)
	player.set_physics_process(false)
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(player)
	return player


func _write_raw(saves: SaveManager, text: String) -> void:
	saves.ensure_directory()
	var file := FileAccess.open(saves.save_path(), FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _find_solid_near(world: VoxelWorld, x: int, z: int) -> Vector3i:
	var height := world.surface_height(x, z)
	for y in range(height, height - 8, -1):
		var cell := Vector3i(x, y, z)
		world.ensure_chunk(VoxelWorld.world_to_chunk(cell))
		if BlockDB.is_solid(world.get_block(cell)):
			return cell
	return Vector3i(x, height, z)


func run(h: TestHarness) -> void:
	_clean()
	var saves := SaveManager.new(TEST_DIRECTORY)
	h.check(saves.ensure_directory(), "the M26 test save directory is available")

	# --- a multi-chunk player build ---------------------------------------
	# Pinned to the M30 terrain: the pristine cells below are asserted on that layout.
	var world := VoxelWorld.new(17017, 1)
	var boundary_x := 15
	var row_y := 90
	var row_z := 8
	# Load both sides of the x=15/16 chunk boundary and the removed-block chunk.
	for x in range(13, 19):
		world.ensure_chunk(VoxelWorld.world_to_chunk(Vector3i(x, row_y, row_z)))
	var removed := _find_solid_near(world, 14, 12)
	world.ensure_chunk(VoxelWorld.world_to_chunk(removed))
	h.check(world.set_block(removed, BlockDB.AIR), "the player removes a generated block")

	var row := [
		[13, BlockDB.STONE_BRICK, 0],
		[14, BlockDB.GLASS, 0],
		[15, BlockDB.STAIR, 1],
		[16, BlockDB.STAIR, 3],
		[17, BlockDB.CRAFTING_TABLE, 0],
		[18, BlockDB.DOOR, 0],
	]
	for entry: Array in row:
		var cell := Vector3i(int(entry[0]), row_y, row_z)
		h.check(world.set_block_state(cell, int(entry[1]), int(entry[2])),
			"the player places %s at x=%d" % [BlockDB.name_of(int(entry[1])), int(entry[0])])

	var player := _spawn_player(world)
	player.teleport_to(Vector3(15.5, float(row_y) + 2.0, 8.5))
	player.look_yaw(90.0)
	player.look_pitch(-12.0)
	player.flying = true
	var inventory := Inventory.new()
	inventory.add(BlockDB.TIMBER_FRAME, 24)
	inventory.add(ItemDB.IRON_INGOT, 6)
	inventory.add(ItemDB.DIAMOND_PICKAXE, 1)
	var clock := DayNight.new(0.42, 900.0)
	var health := Health.new(20.0, 13.0)
	var breath := 4.5
	var hunger := 11.0
	var stations := [{"x": 17, "y": row_y, "z": row_z, "kind": "table",
		"contents": [[BlockDB.PLANKS, 5]]}]
	var crops := [[16, row_y, row_z, 3.5]]
	var npcs := {"settlements": [{"id": "home", "store": {BlockDB.PLANKS: 12}}],
		"npcs": [{"id": "ada", "name": "Ada", "role": "woodcutter"}]}

	h.check(saves.write(world, player, inventory, clock, health, breath, hunger, npcs, stations, crops),
		"the multi-chunk build is written")
	h.check(FileAccess.file_exists(saves.save_path()), "the save exists on disk")
	h.check(not FileAccess.file_exists(saves.save_path() + ".bak"),
		"a completed write leaves no backup file")

	# --- apply to a fresh session (simulated restart) ---------------------
	var result: Dictionary = saves.read()
	h.check(bool(result["ok"]), "the multi-chunk save reads back")
	var restored := VoxelWorld.new(17017, 1)
	for x in range(13, 19):
		restored.ensure_chunk(VoxelWorld.world_to_chunk(Vector3i(x, row_y, row_z)))
	var restored_player := _spawn_player(restored)
	var restored_inventory := Inventory.new()
	var restored_clock := DayNight.new(0.0, 900.0)
	var restored_health := Health.new()
	var applied: Dictionary = saves.apply(result, restored, restored_player, restored_inventory,
		restored_clock, restored_health)
	h.check(bool(applied["ok"]), "the multi-chunk save applies")

	for entry: Array in row:
		var cell := Vector3i(int(entry[0]), row_y, row_z)
		h.eq(restored.get_block(cell), int(entry[1]),
			"restored block at x=%d" % int(entry[0]))
		h.eq(restored.get_orientation(cell), int(entry[2]),
			"restored orientation at x=%d" % int(entry[0]))
	h.eq(restored.get_block(removed), BlockDB.AIR, "the removed block stays removed")
	h.approx(restored_player.global_position.x, 15.5, 1e-3, "the player x position survives")
	h.approx(restored_player.global_position.y, float(row_y) + 2.0, 1e-3, "the player y position survives")
	h.check(restored_player.flying, "the player flying state survives")
	h.eq(restored_inventory.count_of(BlockDB.TIMBER_FRAME), 24, "the inventory blocks survive")
	h.eq(restored_inventory.count_of(ItemDB.IRON_INGOT), 6, "the inventory ingots survive")
	h.eq(restored_inventory.count_of(ItemDB.DIAMOND_PICKAXE), 1, "the crafted tool survives")
	h.approx(restored_clock.time_of_day, 0.42, 1e-6, "the clock survives")
	h.approx(restored_health.health, 13.0, 1e-6, "the health survives")
	h.approx(float(applied["breath"]), 4.5, 1e-6, "the breath survives")
	h.approx(float(applied["hunger"]), 11.0, 1e-6, "the hunger survives")
	h.eq((applied["stations"] as Array).size(), 1, "the station payload survives")
	h.eq((applied["crops"] as Array).size(), 1, "the crop payload survives")
	h.eq((applied["npcs"] as Dictionary).size(), 2, "the resident/settlement payload survives")

	# --- moving out of range: unload and regenerate the far chunk ---------
	var far_chunk := VoxelWorld.world_to_chunk(Vector3i(16, row_y, row_z))
	restored.unload_chunk(far_chunk)
	h.check(not restored.has_chunk(far_chunk), "the far half of the build unloads")
	restored.ensure_chunk(far_chunk)
	for entry: Array in row:
		if int(entry[0]) < 16:
			continue
		var cell := Vector3i(int(entry[0]), row_y, row_z)
		h.eq(restored.get_block(cell), int(entry[1]),
			"unloaded/reloaded block at x=%d survives" % int(entry[0]))
		h.eq(restored.get_orientation(cell), int(entry[2]),
			"unloaded/reloaded orientation at x=%d survives" % int(entry[0]))

	# --- a full reset plus re-apply simulates reopening the save ----------
	restored.clear_edits()
	h.eq(restored.get_block(Vector3i(15, row_y, row_z)), BlockDB.AIR,
		"clearing edits restores pristine generation")
	var reopened: Dictionary = saves.read()
	var reapplied: Dictionary = saves.apply(reopened, restored, restored_player, restored_inventory)
	h.check(bool(reapplied["ok"]), "the save re-applies after a full reset")
	h.eq(restored.get_block(Vector3i(15, row_y, row_z)), BlockDB.STAIR,
		"the boundary stair returns on reopen")
	h.eq(restored.get_orientation(Vector3i(15, row_y, row_z)), 1,
		"the boundary stair orientation returns on reopen")
	h.eq(restored.get_block(Vector3i(16, row_y, row_z)), BlockDB.STAIR,
		"the neighbouring stair returns on reopen")
	h.eq(restored.get_orientation(Vector3i(16, row_y, row_z)), 3,
		"the neighbouring stair orientation returns on reopen")

	# --- interrupted write: the old save is recoverable -------------------
	var absolute := ProjectSettings.globalize_path(saves.save_path())
	var absolute_backup := ProjectSettings.globalize_path(saves.save_path() + ".bak")
	h.check(DirAccess.rename_absolute(absolute, absolute_backup) == OK,
		"an interrupted write can be simulated by moving the save aside")
	h.check(not FileAccess.file_exists(saves.save_path()), "the save is missing during the interruption")
	var recovered: Dictionary = saves.read()
	h.check(bool(recovered["ok"]), "read() recovers the save moved aside by an interrupted write")
	h.check(FileAccess.file_exists(saves.save_path()), "the recovered save is back at the normal path")
	h.check(not FileAccess.file_exists(saves.save_path() + ".bak"), "recovery consumes the backup")

	# --- a corrupt payload is rejected without mutating a live world ------
	var before_hash := restored.fingerprint()
	var before_player := restored_player.global_position
	_write_raw(saves, "{ this is not a save")
	var rejected: Dictionary = saves.read()
	h.check(not bool(rejected["ok"]), "a corrupt save is rejected")
	h.eq(restored.fingerprint(), before_hash, "a rejected save leaves the world untouched")
	h.eq(restored_player.global_position, before_player, "a rejected save leaves the player untouched")
	h.check(not FileAccess.file_exists(saves.save_path()), "the corrupt save is quarantined")

	var tree := Engine.get_main_loop() as SceneTree
	tree.root.remove_child(player)
	player.free()
	tree.root.remove_child(restored_player)
	restored_player.free()
	_clean()
	h.finish()

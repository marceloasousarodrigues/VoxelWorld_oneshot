extends SceneTree

## Runtime visual-acceptance capture for M41c (first-person hand and tool polish).
##
## Boots the real game scene, stages the player in the project's existing
## `VisualTestArena`, and captures the wooden pickaxe in the five required states:
## idle, facing a nearby block, walking, mining/swing, and shade.  It then records
## the axe, shovel and sword in the same presentation so they can be judged to the
## same standard.
##
## Usage:
##   godot --path godot --script res://scripts/tests/run_m41c_demo.gd
##
## Frames and a manifest are written to prototypes/m17/results/godot/.  This is
## evidence tooling, not game code: it never changes inventory, tool or gameplay
## rules.

const RESULTS := "res://../prototypes/m17/results/godot"
const FRAME_PREFIX := "m41c-demo"
const BLOCK_CELL := Vector3i(71, 66, -82)

var _game
var _frames: Array[String] = []
var _notes: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_main")


func _main() -> void:
	var scene: PackedScene = load("res://scenes/game.tscn")
	_game = scene.instantiate()
	root.add_child(_game)
	if int(_game.state) == 0:
		_game._options["visual_test"] = "m41c"
		_game._start_world(17017, null)
	var guard := 0
	while int(_game.state) != 2 and guard < 20000:
		await process_frame
		guard += 1
	if int(_game.state) != 2:
		print("M41C_DEMO_FAIL never reached PLAYING")
		quit(1)
		return

	# The established capture viewpoint: inside the south gate on the path,
	# facing the cottage.  The HUD reticle is at the screen centre.
	_game.player.teleport_to(Vector3(71.5, 66.05, -79.0))
	_game.player.look_yaw(0.0)
	_game.player.look_pitch(-4.0)
	_game.streamer.focus_at(_game.player.global_position)
	await _settle()

	_seed_loadout()
	_game.player.set_camera_mode(VoxelPlayer.CAMERA_FIRST)
	_game.inventory.select(0)
	_game.player.refresh_visuals()
	await _settle()

	# 1. Idle, facing a clear area.
	await _capture("pickaxe idle, clear area",
		{"camera": "first_person", "tool": "wood_pickaxe", "state": "idle"})

	# 2. Facing a nearby block.  Place one solid block on the path ahead through
	# the real world API; this is a staging aid, not a gameplay change.
	_game.world.set_block(BLOCK_CELL, BlockDB.STONE)
	_game.world.set_block(BLOCK_CELL + Vector3i.UP, BlockDB.STONE)
	_game.player.look_pitch(-8.0)
	for index in 12:
		await process_frame
	await _capture("pickaxe facing nearby block",
		{"camera": "first_person", "tool": "wood_pickaxe", "state": "near_block"})

	# 3. Walking.  The staged block is removed first so the player walks along the
	# open path instead of colliding with it and filling the frame at the near
	# plane.  The block is restored for the swing frame below.
	_game.world.set_block(BLOCK_CELL, BlockDB.AIR)
	_game.world.set_block(BLOCK_CELL + Vector3i.UP, BlockDB.AIR)
	_game.player.look_pitch(-4.0)
	Input.action_press("move_forward")
	for index in 16:
		await physics_frame
	await _capture("pickaxe walking",
		{"camera": "first_person", "tool": "wood_pickaxe", "state": "walking"})
	Input.action_release("move_forward")
	for index in 12:
		await physics_frame

	# Return to the staged spot so the swing reads against the block.
	_game.world.set_block(BLOCK_CELL, BlockDB.STONE)
	_game.world.set_block(BLOCK_CELL + Vector3i.UP, BlockDB.STONE)
	_game.player.teleport_to(Vector3(71.5, 66.05, -79.0))
	_game.player.look_yaw(0.0)
	_game.player.look_pitch(-8.0)
	for index in 8:
		await process_frame
	_game.player.play_swing_animation()
	for index in 5:
		await process_frame
	await _capture("pickaxe mining swing",
		{"camera": "first_person", "tool": "wood_pickaxe", "state": "swing"})
	# The staging block is no longer needed; clear it before the remaining tool
	# captures so their silhouettes read against the open path.
	_game.world.set_block(BLOCK_CELL, BlockDB.AIR)
	_game.world.set_block(BLOCK_CELL + Vector3i.UP, BlockDB.AIR)
	for index in 12:
		await process_frame

	# 4. Shaded area.  The stair-roofed pavilion at the arena centre has a solid
	# roof and open sides, so the tool is lit by ambient/bounce light only.
	_game.player.teleport_to(Vector3(73.5, 66.05, -90.5))
	_game.player.look_yaw(0.0)
	_game.player.look_pitch(-4.0)
	_game.streamer.focus_at(_game.player.global_position)
	await _settle()
	await _capture("pickaxe in shade under pavilion roof",
		{"camera": "first_person", "tool": "wood_pickaxe", "state": "shade"})

	# Return to the open path for the equivalent tool captures.
	_game.player.teleport_to(Vector3(71.5, 66.05, -79.0))
	_game.player.look_yaw(0.0)
	_game.player.look_pitch(-4.0)
	_game.streamer.focus_at(_game.player.global_position)
	await _settle()
	var tools := [
		[1, "stone_axe", "axe"],
		[2, "iron_shovel", "shovel"],
		[3, "diamond_sword", "sword"],
	]
	for entry: Array in tools:
		_game.inventory.select(int(entry[0]))
		_game.player.refresh_visuals()
		for index in 12:
			await process_frame
		await _capture("%s first person" % str(entry[1]),
			{"camera": "first_person", "tool": str(entry[1]), "state": "idle"})
		if str(entry[1]) == "stone_axe":
			_game.player.play_swing_animation()
			for index in 5:
				await process_frame
			await _capture("axe swing",
				{"camera": "first_person", "tool": "stone_axe", "state": "swing"})

	# First-person jump: the whole hand/item assembly lifts with the arm, so the
	# grip must remain continuous in the air.
	_game.inventory.select(0)
	_game.player.refresh_visuals()
	_game.player.set_camera_mode(VoxelPlayer.CAMERA_FIRST)
	_game.player.look_yaw(0.0)
	_game.player.look_pitch(-4.0)
	for index in 12:
		await process_frame
	Input.action_press("jump")
	for index in 7:
		await physics_frame
	await _capture("pickaxe jumping",
		{"camera": "first_person", "tool": "wood_pickaxe", "state": "jump"})
	Input.action_release("jump")
	for index in 55:
		await physics_frame

	# One third-person frame confirms the shared character and camera path still
	# present the selected tool; the camera itself is untouched by this pass.
	_game.player.camera_distance = 3.8
	_game.player.camera_shoulder = 0.7
	_game.player.set_camera_mode(VoxelPlayer.CAMERA_THIRD)
	for index in 60:
		await process_frame
	await _capture("third-person pickaxe",
		{"camera": "third_person", "tool": "wood_pickaxe", "state": "idle"})

	_write_manifest()
	print("M41C_DEMO_DONE frames=%d" % _frames.size())
	quit(0)


func _seed_loadout() -> void:
	var inventory = _game.inventory
	for index in Inventory.HOTBAR_SIZE:
		inventory.clear_slot(index)
	inventory.put_stack(0, {"item": ItemDB.WOOD_PICKAXE, "count": 1,
		"durability": ItemDB.max_durability(ItemDB.WOOD_PICKAXE)})
	inventory.put_stack(1, {"item": ItemDB.STONE_AXE, "count": 1,
		"durability": ItemDB.max_durability(ItemDB.STONE_AXE)})
	inventory.put_stack(2, {"item": ItemDB.IRON_SHOVEL, "count": 1,
		"durability": ItemDB.max_durability(ItemDB.IRON_SHOVEL)})
	inventory.put_stack(3, {"item": ItemDB.DIAMOND_SWORD, "count": 1,
		"durability": ItemDB.max_durability(ItemDB.DIAMOND_SWORD)})
	inventory.put_stack(4, {"item": ItemDB.STONE_PICKAXE, "count": 1,
		"durability": ItemDB.max_durability(ItemDB.STONE_PICKAXE)})
	inventory.put_stack(5, {"item": BlockDB.STONE, "count": 16})
	inventory.select(0)
	_game.player.refresh_visuals()


func _capture(note: String, extra: Dictionary = {}) -> void:
	await RenderingServer.frame_post_draw
	var directory := ProjectSettings.globalize_path(RESULTS)
	if not DirAccess.dir_exists_absolute(directory):
		DirAccess.make_dir_recursive_absolute(directory)
	var filename := "%s-%02d.png" % [FRAME_PREFIX, _frames.size()]
	var path := directory.path_join(filename)
	var image := root.get_texture().get_image()
	var error := image.save_png(path)
	if error != OK:
		push_error("M41C_DEMO_CAPTURE_FAILED %s (%d)" % [path, error])
		return
	_frames.append(filename)
	var record := extra.duplicate()
	record["note"] = note
	record["file"] = filename
	if _game != null and _game.player != null:
		record["camera_distance"] = _game.player.current_camera_distance()
		record["camera_shoulder"] = _game.player.camera_shoulder
		var arms = _game.player.first_person_arms
		var view_size: Vector2 = _game.player.camera.get_viewport().get_visible_rect().size
		var bounds: Rect2 = arms.screen_bounds(_game.player.camera)
		record["arm_screen_bounds"] = [bounds.position.x, bounds.position.y,
			bounds.size.x, bounds.size.y]
		record["arm_screen_fraction"] = [bounds.size.x / view_size.x,
			bounds.size.y / view_size.y]
		record["reticle_top_local"] = arms.reticle_top()
		record["reticle_clear"] = arms.reticle_clear()
	_notes.append(record)
	print("M41C_DEMO_FRAME %s %s" % [filename, note])


func _settle() -> void:
	for index in 900:
		if _game.streamer.is_settled():
			break
		await process_frame
	for index in 30:
		await physics_frame
	for index in 8:
		await process_frame


func _write_manifest() -> void:
	var directory := ProjectSettings.globalize_path(RESULTS)
	var path := directory.path_join("%s-manifest.json" % FRAME_PREFIX)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"evidence": "frames captured from the running Godot viewport by run_m41c_demo.gd",
		"frames": _notes,
	}, "\t") + "\n")
	file.close()

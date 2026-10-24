extends SceneTree

## Runtime visual-acceptance capture for M41's second visual pass.
##
## Boots the real game scene at the normal spawn, then records first-person
## pickaxe/axe/shovel/sword frames and a third-person idle/walk/swing/jump/sword
## sequence.  This is evidence tooling, not game code.
##
## Usage:
##   godot --path godot --script res://scripts/tests/run_camera_demo.gd
##
## Frames and a manifest are written to prototypes/m17/results/godot/.

const RESULTS := "res://../prototypes/m17/results/godot"
const FRAME_PREFIX := "m41b-demo"

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
		# Use the project's existing lush showcase arena so the visual comparison
		# is against a representative world, not the spawn terrace's sky island.
		_game._options["visual_test"] = "m41b"
		_game._start_world(17017, null)
	var guard := 0
	while int(_game.state) != 2 and guard < 20000:
		await process_frame
		guard += 1
	if int(_game.state) != 2:
		print("M41B_DEMO_FAIL never reached PLAYING")
		quit(1)
		return

	# Stand on the path inside the gate, looking north towards the cottage with
	# the market on the right.  The rear camera has open path behind it.
	_game.player.teleport_to(Vector3(71.5, 66.05, -79.0))
	_game.player.look_yaw(0.0)
	_game.player.look_pitch(-4.0)
	_game.streamer.focus_at(_game.player.global_position)
	await _settle()

	_seed_loadout()
	_game.player.set_camera_mode(VoxelPlayer.CAMERA_FIRST)
	_game.player.look_yaw(0.0)
	_game.player.look_pitch(-4.0)
	await _settle()

	# First person: one frame per tool, using the real held-item builder.
	var first_person_tools := [
		[0, "first-person pickaxe"],
		[1, "first-person axe"],
		[2, "first-person shovel"],
		[3, "first-person sword"],
	]
	for entry: Array in first_person_tools:
		_game.inventory.select(int(entry[0]))
		_game.player.refresh_visuals()
		for index in 10:
			await process_frame
		await _capture(str(entry[1]), {"camera": "first_person"})

	# Third person: the character is left of the crosshair, with the tool in the
	# right hand.  Keep the normal arena view so the composition is representative.
	# A stone pickaxe is used here because its grey head reads against the timber
	# buildings; the wooden one is still the first-person pickaxe above.
	_game.inventory.select(4)
	_game.player.refresh_visuals()
	_game.player.camera_distance = 3.8
	_game.player.camera_shoulder = 0.7
	_game.player.set_camera_mode(VoxelPlayer.CAMERA_THIRD)
	for index in 80:
		await process_frame
	await _capture("third-person idle pickaxe", {"camera": "third_person"})

	# Walking towards the cottage keeps the camera on open grass behind the
	# player, so this frame shows locomotion rather than a collision close-up.
	Input.action_press("move_forward")
	for index in 18:
		await physics_frame
	await _capture("third-person walking", {"camera": "third_person", "action": "walk"})
	Input.action_release("move_forward")
	for index in 24:
		await physics_frame

	# Jump.
	Input.action_press("jump")
	for index in 7:
		await physics_frame
	await _capture("third-person jumping", {"camera": "third_person", "action": "jump"})
	Input.action_release("jump")
	for index in 45:
		await physics_frame

	# Tool use: the shared swing pose with the pickaxe.
	_game.player.play_swing_animation()
	for index in 5:
		await process_frame
	await _capture("third-person pickaxe swing",
		{"camera": "third_person", "action": "swing"})

	# A second tool in third person, so the sword's grip/orientation is visible.
	_game.inventory.select(3)
	_game.player.refresh_visuals()
	for index in 30:
		await process_frame
	await _capture("third-person sword", {"camera": "third_person", "item": "diamond_sword"})

	# Back to first person with a fresh swing.
	_game.inventory.select(1)
	_game.player.refresh_visuals()
	_game.player.set_camera_mode(VoxelPlayer.CAMERA_FIRST)
	_game.player.play_swing_animation()
	for index in 5:
		await process_frame
	await _capture("first-person axe swing",
		{"camera": "first_person", "action": "swing"})

	_write_manifest()
	print("M41B_DEMO_DONE frames=%d" % _frames.size())
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
		push_error("M41B_DEMO_CAPTURE_FAILED %s (%d)" % [path, error])
		return
	_frames.append(filename)
	var record := extra.duplicate()
	record["note"] = note
	record["file"] = filename
	if _game != null and _game.player != null:
		record["camera_distance"] = _game.player.current_camera_distance()
		record["camera_shoulder"] = _game.player.camera_shoulder
	_notes.append(record)
	print("M41B_DEMO_FRAME %s %s" % [filename, note])


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
		"evidence": "frames captured from the running Godot viewport by run_camera_demo.gd",
		"frames": _notes,
	}, "\t") + "\n")
	file.close()

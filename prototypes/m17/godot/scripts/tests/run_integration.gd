extends SceneTree

## Runtime integration test: boots the real game scene and exercises the parts a
## headless unit test cannot reach -- spawn, collision settlement, WASD movement,
## and the pause/resume input path.
##
## Usage:
##   godot --headless --path prototypes/m17/godot \
##     --script res://scripts/tests/run_integration.gd -- --straight-to-game
##
## Exits 0 when every check passes, 1 otherwise, 2 when the game never starts.

var _game: Node
var _failures: Array[String] = []
var _passes := 0


func _initialize() -> void:
	call_deferred("_main")


func _check(condition: bool, description: String) -> void:
	if condition:
		_passes += 1
		print("M17_INT_ASSERT_PASS %s" % description)
	else:
		_failures.append(description)
		print("M17_INT_ASSERT_FAIL %s" % description)


func _main() -> void:
	var scene: PackedScene = load("res://scenes/game.tscn")
	_game = scene.instantiate()
	root.add_child(_game)

	var guard := 0
	while int(_game.state) != 2 and guard < 20000:
		await process_frame
		guard += 1
	if int(_game.state) != 2:
		print("M17_INTEGRATION_FAIL never reached PLAYING (state %d)" % int(_game.state))
		quit(2)
		return

	var player = _game.player
	_check(player.is_physics_processing(), "the player's physics process is enabled in play")

	# Exercise the game-owned death signal path and activate the actual button
	# signal (headless does not synthesize a visible mouse click).
	_game.health.set_health(1.0)
	_game.health.apply_damage(1.0, "integration")
	await process_frame
	_check(int(_game.state) == 4, "lethal health transition enters DEAD")
	_check(not player.is_physics_processing(), "death disables player physics")
	_check(not player.can_interact, "death disables player interaction/input")
	_check(_game.death_screen.is_open(), "death overlay is visible")
	var buttons: Array[Node] = _game.death_screen.find_children("*", "Button", true, false)
	var respawn_button: Button = buttons[0] as Button if not buttons.is_empty() else null
	_check(respawn_button != null, "death overlay contains Respawn button")
	if respawn_button != null:
		respawn_button.pressed.emit()
	await process_frame
	_check(int(_game.state) == 2, "Respawn button signal returns to PLAYING")
	_check(is_equal_approx(_game.health.health, _game.health.max_health), "respawn restores full health")
	_check(is_equal_approx(_game.breath, Survival.MAX_BREATH), "respawn restores full breath")
	_check(player.is_physics_processing(), "respawn enables player physics")
	_check(player.can_interact, "respawn enables player input")
	_check(_game.death_screen != null and not _game.death_screen.is_open(), "respawn hides death overlay")
	_check(_game.world.get_block(Vector3i(floori(player.global_position.x), floori(player.global_position.y - 1), floori(player.global_position.z))) != BlockDB.AIR,
		"respawn places player over a valid solid spawn")

	# Let gravity settle the player onto the terrain.
	for i in range(90):
		await physics_frame
	var landed: Vector3 = player.global_position
	var ground_below: int = _game.world.get_block(Vector3i(floori(landed.x), floori(landed.y - 1.0), floori(landed.z)))
	_check(player.is_on_floor(), "the player is standing on the ground after settling (y=%.3f)" % landed.y)
	_check(bool(_game.world.get_block(Vector3i(floori(landed.x), floori(landed.y) - 1, floori(landed.z))) != BlockDB.AIR),
		"there is a solid block under the player (block %d)" % ground_below)
	# The feet must rest on top of that block, not sink into it.
	var feet_fraction: float = landed.y - floorf(landed.y)
	_check(feet_fraction < 0.2 or feet_fraction > 0.8,
		"the player rests on a block boundary, not sunk into the terrain (fraction %.3f)" % feet_fraction)

	# Forward movement.
	var before: Vector3 = player.global_position
	Input.action_press("move_forward")
	for i in range(45):
		await physics_frame
	Input.action_release("move_forward")
	var forward := Vector2(player.global_position.x - before.x, player.global_position.z - before.z)
	_check(forward.length() > 0.5, "WASD forward moves the player horizontally (%.3f units)" % forward.length())

	# Strafing.
	before = player.global_position
	Input.action_press("move_right")
	for i in range(45):
		await physics_frame
	Input.action_release("move_right")
	var strafe := Vector2(player.global_position.x - before.x, player.global_position.z - before.z)
	_check(strafe.length() > 0.5, "WASD strafe moves the player horizontally (%.3f units)" % strafe.length())

	# Backward should move opposite to forward, not in a fixed direction.
	before = player.global_position
	Input.action_press("move_backward")
	for i in range(45):
		await physics_frame
	Input.action_release("move_backward")
	var back: Vector3 = player.global_position - before
	_check(Vector2(back.x, back.z).length() > 0.5, "WASD backward moves the player (%.3f units)" % Vector2(back.x, back.z).length())

	# Movement must still work after pausing and resuming.
	_game._pause()
	await process_frame
	await process_frame
	_game._resume()
	await physics_frame
	before = player.global_position
	Input.action_press("move_forward")
	for i in range(45):
		await physics_frame
	Input.action_release("move_forward")
	var resumed: Vector3 = player.global_position - before
	_check(Vector2(resumed.x, resumed.z).length() > 0.5,
		"WASD still works after pause then resume (%.3f units)" % Vector2(resumed.x, resumed.z).length())

	# Block placement and breaking through the real player controller.  The player
	# hovers above the ground so the placement cell is clear of its own body (the
	# controller correctly refuses to build inside the player).
	player.flying = true
	player.teleport_to(Vector3(8.5, 74.0, 8.5))
	player.look_yaw(0.0)
	player.look_pitch(-89.0)
	for i in range(3):
		await process_frame
	var target: Dictionary = player.target()
	_check(target.get("hit", false), "looking straight down targets the ground")
	if target.get("hit", false):
		var ground_cell: Vector3i = target["block"]
		var place_cell: Vector3i = ground_cell + target["normal"]
		_check(int(_game.world.get_block(ground_cell)) != BlockDB.AIR, "the targeted cell starts solid")
		var placed: bool = player.place_selected()
		await process_frame
		_check(placed, "place_selected() places a block on the targeted face")
		_check(int(_game.world.get_block(place_cell)) != BlockDB.AIR, "the world reflects the placed block")
		var broke: bool = player.break_target()
		await process_frame
		_check(broke, "break_target() removes the targeted block")
		_check(int(_game.world.get_block(place_cell)) == BlockDB.AIR, "the world reflects the broken block")
	player.flying = false

	# Walking across a chunk boundary keeps the player grounded and streams the
	# neighbouring chunk in.
	player.spawn_on_column(14, 8)
	player.look_yaw(-90.0)
	player.look_pitch(0.0)
	for i in range(30):
		await physics_frame
	var boundary_start: Vector3 = player.global_position
	var neighbour: Vector3i = ChunkStreamer.chunk_of(boundary_start) + Vector3i(1, 0, 0)
	Input.action_press("move_forward")
	for i in range(120):
		await physics_frame
	Input.action_release("move_forward")
	var crossed: Vector3 = player.global_position
	_check(crossed.x > boundary_start.x + 2.0, "the player walks toward the chunk boundary (dx=%.2f)" % (crossed.x - boundary_start.x))
	_check(player.is_on_floor(), "the player stays on the floor while crossing chunks")
	_check(_game.world.has_chunk(neighbour), "the neighbouring chunk is streamed in (%s)" % str(neighbour))

	if _failures.is_empty():
		print("M17_INTEGRATION_PASS %d assertions" % _passes)
		quit(0)
	else:
		for failure: String in _failures:
			print("M17_INTEGRATION_FAILURE %s" % failure)
		print("M17_INTEGRATION_FAIL %d failures, %d passes" % [_failures.size(), _passes])
		quit(1)

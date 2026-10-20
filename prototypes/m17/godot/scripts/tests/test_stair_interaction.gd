extends RefCounted

## Player-facing placement and mining contract for the M23 stair.


func name() -> String:
	return "stair player interaction"


func run(h: TestHarness) -> void:
	var world := VoxelWorld.new(17017)
	var chunk := ChunkData.new(Vector3i.ZERO)
	chunk.generated = true
	world.adopt_chunk(chunk)
	world.set_block(Vector3i(8, 8, 8), BlockDB.STONE)
	world.set_block(Vector3i(10, 8, 8), BlockDB.STONE)
	var player := VoxelPlayer.new()
	player.world = world
	player.inventory = Inventory.new()
	player.set_process(false)
	player.set_physics_process(false)
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(player)
	player.teleport_to(Vector3(100.0, 100.0, 100.0))
	player.inventory.add(BlockDB.STAIR, 2)
	player.look_yaw(-90.0)

	player._hit = {"hit": true, "block": Vector3i(8, 8, 8), "normal": Vector3i.UP}
	h.check(player.place_selected(), "the player can place a stair above a targeted block")
	h.eq(world.get_block(Vector3i(8, 9, 8)), BlockDB.STAIR, "placement writes the stair block id")
	h.eq(world.get_orientation(Vector3i(8, 9, 8)), 1, "placement uses the camera's nearest +X facing")

	player._hit = {"hit": true, "block": Vector3i(10, 8, 8), "normal": Vector3i.DOWN}
	h.check(player.place_selected(), "the player can place a stair under a targeted block")
	h.eq(world.get_orientation(Vector3i(10, 7, 8)), 5, "a downward hit selects upside-down +X orientation")

	player._hit = {"hit": true, "block": Vector3i(8, 9, 8), "normal": Vector3i.UP,
		"block_id": BlockDB.STAIR}
	h.check(player.break_target(), "the player can mine the placed stair")
	h.eq(world.get_block(Vector3i(8, 9, 8)), BlockDB.AIR, "mining removes the stair")
	h.eq(world.get_orientation(Vector3i(8, 9, 8)), 0, "mining clears the stair orientation")

	# R cycles an explicit facing, which overrides the camera so a roof row can
	# be built while looking along the wall.  The live preview mirrors the same
	# placement rules the HUD uses.
	player.placement_facing = -1
	h.eq(player.rotate_placement(), 0, "R starts at the +Z facing")
	h.eq(player.rotate_placement(), 1, "R cycles to +X")
	h.eq(player.rotate_placement(), 2, "R cycles to -Z")
	h.eq(player.rotate_placement(), 3, "R cycles to -X")
	h.eq(player.rotate_placement(), 0, "R wraps back to +Z")
	player.look_yaw(180.0)  # camera faces -Z; the explicit +Z rotation must win
	player._hit = {"hit": true, "block": Vector3i(10, 8, 8), "normal": Vector3i.UP,
		"block_id": BlockDB.STONE}
	h.eq(player.placement_orientation(Vector3i.UP), 0, "the explicit rotation overrides the camera")
	var preview: Dictionary = player.placement_preview()
	h.check(bool(preview.get("valid", false)), "the build preview accepts a clear aimed face")
	h.eq(preview.get("normal", Vector3i.ZERO), Vector3i.UP, "the preview reports the aimed face")
	player._hit = {"hit": true, "block": Vector3i(10, 7, 8), "normal": Vector3i.UP,
		"block_id": BlockDB.STONE}
	var occupied := player.placement_preview()
	h.check(not bool(occupied.get("valid", true)), "the preview refuses an occupied cell")
	h.check(str(occupied.get("reason", "")).contains("occupied"), "the preview explains the occupied cell")
	player._hit = {"hit": true, "block": Vector3i(100, 99, 100), "normal": Vector3i.UP,
		"block_id": BlockDB.STONE}
	var inside := player.placement_preview()
	h.check(not bool(inside.get("valid", true)), "the preview refuses a cell inside the player")
	h.eq(str(inside.get("reason", "")), "inside you", "the preview explains the body collision")

	tree.root.remove_child(player)
	player.free()
	h.finish()

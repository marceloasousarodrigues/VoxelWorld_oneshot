extends SceneTree

## Runtime integration test: boots the real game scene and exercises the parts a
## headless unit test cannot reach -- spawn, collision settlement, WASD movement,
## and the pause/resume input path.
##
## Usage:
##   godot --headless --path godot \
##     --script res://scripts/tests/run_integration.gd -- --straight-to-game
##
## Exits 0 when every check passes, 1 otherwise, 2 when the game never starts.

var _game: Node
var _failures: Array[String] = []
var _passes := 0
var _test_pad_y := 69
const CreatureScript = preload("res://scripts/game/passive_creature.gd")
const CreatureModel = preload("res://scripts/core/passive_creatures.gd")
const HostileScript = preload("res://scripts/game/hostile_creature.gd")
const HostileModel = preload("res://scripts/core/hostile_creatures.gd")
const NpcModel = preload("res://scripts/core/npc.gd")
const SettlementModel = preload("res://scripts/core/settlement.gd")
const RaidModel = preload("res://scripts/core/raid.gd")
const StationModel = preload("res://scripts/core/station.gd")
const FinalDemo = preload("res://scripts/game/final_demo.gd")


func _initialize() -> void:
	call_deferred("_main")


func _check(condition: bool, description: String) -> void:
	if condition:
		_passes += 1
		print("M17_INT_ASSERT_PASS %s" % description)
	else:
		_failures.append(description)
		print("M17_INT_ASSERT_FAIL %s" % description)


## Build a small, flat interaction area above the highest local column so these
## player-control checks stay independent of generated terrain height.
func _prepare_test_pad(center: Vector2i = Vector2i(8, 8), radius: int = 6) -> void:
	var highest_surface := 1
	for z in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			highest_surface = maxi(highest_surface, _game.world.surface_height(x, z))
	_test_pad_y = mini(highest_surface + 2, WorldGen.WORLD_HEIGHT - 8)
	for z in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			var surface: int = int(_game.world.surface_height(x, z))
			for y in range(surface + 1, mini(_test_pad_y + 10, WorldGen.WORLD_HEIGHT)):
				_game.world.set_block(Vector3i(x, y, z), BlockDB.AIR)
			_game.world.set_block(Vector3i(x, _test_pad_y, z), BlockDB.STONE)


# --- reached-geometry helpers for the edit regressions --------------------

const FACE_EPS := 0.001


func _triangle_matches(a: Vector3, b: Vector3, c: Vector3, centre: Vector3, outward: Vector3) -> bool:
	if absf((a - centre).dot(outward)) > FACE_EPS:
		return false
	if absf((b - centre).dot(outward)) > FACE_EPS:
		return false
	if absf((c - centre).dot(outward)) > FACE_EPS:
		return false
	if ((a + b + c) / 3.0 - centre).length() > 0.6:
		return false
	return (b - a).cross(c - a).dot(outward) < 0.0


func _mesh_has_face(mesh: ArrayMesh, centre: Vector3, outward: Vector3) -> bool:
	if mesh == null:
		return false
	for surface in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var i := 0
		while i + 2 < indices.size():
			if _triangle_matches(vertices[int(indices[i])], vertices[int(indices[i + 1])],
					vertices[int(indices[i + 2])], centre, outward):
				return true
			i += 3
	return false


func _faces_have(faces: PackedVector3Array, centre: Vector3, outward: Vector3) -> bool:
	var i := 0
	while i + 2 < faces.size():
		if _triangle_matches(faces[i], faces[i + 1], faces[i + 2], centre, outward):
			return true
		i += 3
	return false


func _collision_shape_faces(view: Node) -> PackedVector3Array:
	var body := view.get_node_or_null("Collision")
	if body == null:
		return PackedVector3Array()
	var shape_node := body.get_child(0) as CollisionShape3D
	if shape_node == null or not (shape_node.shape is ConcavePolygonShape3D):
		return PackedVector3Array()
	return (shape_node.shape as ConcavePolygonShape3D).get_faces()


func _collision_triangle_count(mesh: ArrayMesh) -> int:
	if mesh == null:
		return 0
	var count := 0
	for surface in mesh.get_surface_count():
		count += (mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return count


func _face_centre(cell: Vector3i, outward: Vector3i) -> Vector3:
	return Vector3(cell) + Vector3(0.5, 0.5, 0.5) + Vector3(outward) * 0.5


## Waits until generation, queued edits and in-flight mesh builds are all
## finished, so the geometry inspected below is the final streamed state.
func _stream_until_settled(max_frames: int = 2400) -> int:
	var streamer: ChunkStreamer = _game.streamer
	var world: VoxelWorld = _game.world
	var guard := 0
	var started := Time.get_ticks_msec()
	# The M32 canopy emits more faces per chunk, so a fixed frame count alone is
	# too tight under CPU contention.  Keep a frame cap for determinism and a
	# wall-clock cap so a genuinely stuck streamer still fails in bounded time.
	while guard < max_frames and Time.get_ticks_msec() - started < 45000:
		await process_frame
		guard += 1
		if guard < 2:
			continue
		if not streamer.is_settled() or streamer.queued_count() > 0:
			continue
		if int(streamer.report()["meshes_in_flight"]) > 0:
			continue
		var dirty := false
		for coord: Vector3i in world.chunks:
			if (world.chunks[coord] as ChunkData).mesh_dirty:
				dirty = true
				break
		if not dirty:
			return guard
	var dirty_names: Array[String] = []
	for coord: Vector3i in world.chunks:
		if (world.chunks[coord] as ChunkData).mesh_dirty:
			dirty_names.append(str(coord))
	print("M17_INT_SETTLE_TIMEOUT report=%s dirty=%d %s" % [
		JSON.stringify(streamer.report()), dirty_names.size(), ", ".join(dirty_names.slice(0, 8))])
	return -1


func _find_enclosed_cell() -> Vector3i:
	var world: VoxelWorld = _game.world
	for coord: Vector3i in VoxelWorld.sorted_coords(world.chunks):
		for local_y in range(2, 14):
			for local_z in range(2, 14):
				for local_x in range(2, 14):
					var cell := VoxelWorld.chunk_origin(coord) + Vector3i(local_x, local_y, local_z)
					if not BlockDB.is_solid(world.get_block(cell)):
						continue
					var enclosed := true
					for offset: Vector3i in [Vector3i.RIGHT, Vector3i.LEFT, Vector3i.UP,
							Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]:
						if not world.is_loaded(cell + offset) or not BlockDB.is_solid(world.get_block(cell + offset)):
							enclosed = false
							break
					if enclosed:
						return cell
	return Vector3i(-999, -999, -999)


## A solid, opaque pair straddling the +Z boundary of two loaded chunks.
func _find_boundary_pair() -> Dictionary:
	var world: VoxelWorld = _game.world
	for coord: Vector3i in VoxelWorld.sorted_coords(world.chunks):
		var neighbour_coord := coord + Vector3i(0, 0, 1)
		if not world.has_chunk(neighbour_coord):
			continue
		for local_y in range(2, 14):
			for local_x in range(2, 14):
				var cell := VoxelWorld.chunk_origin(coord) + Vector3i(local_x, local_y, 15)
				var behind := cell + Vector3i(0, 0, 1)
				if BlockDB.opaque[world.get_block(cell)] == 1 and BlockDB.opaque[world.get_block(behind)] == 1:
					return {"target": cell, "edited": coord, "neighbour": neighbour_coord}
	return {}


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
	for i in range(75):
		await process_frame
	_check(_game.creature_nodes.size() <= 6, "live passive population remains capped")
	_check(_game.creature_nodes.size() > 0, "a passive boar spawns in valid nearby terrain")

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
	# The close-range creature ray uses a flat interaction pad away from the
	# starter cottage, so generated vegetation/slope cannot hide the target.
	_prepare_test_pad(Vector2i(24, 24), 6)
	# Exercise the creature damage/death/drop path through the real scene node and
	# game inventory integration (three separate player attacks, one drop).
	var meat_before: int = _game.inventory.count_of(ItemDB.RAW_MEAT)
	var hide_before: int = _game.inventory.count_of(ItemDB.HIDE)
	var oak_before: int = _game.inventory.count_of(BlockDB.OAK_LOG)
	player.flying = true
	# Use the flat interaction pad for the close-range creature ray.  Terrain and
	# vegetation around the natural spawn are allowed to vary; the pad keeps this
	# check about target priority, not about whether a slope blocks the ray.
	player.teleport_to(Vector3(24.5, float(_test_pad_y) + 1.05, 24.5))
	player.look_yaw(0.0)
	player.look_pitch(-25.0)
	await physics_frame
	await process_frame
	# Place the test target on the actual camera ray. Terrain profiles can change
	# the settled player height; a fixed downward offset can put a close target
	# below the ray or behind a voxel and make a failed attack loop forever.
	var ray_forward: Vector3 = -player.camera.global_basis.z
	var creature_position: Vector3 = player.camera.global_position + ray_forward * 1.8
	var creature_state := {"id": 9001, "species": "boar", "position": creature_position,
		"health": CreatureDB.health("boar"), "alive": true, "wander": Vector3.ZERO, "key": "integration-boar"}
	var test_creature = CreatureScript.new()
	test_creature.configure(creature_state, _game.world)
	_game.creature_root.add_child(test_creature)
	test_creature.killed.connect(_game._on_creature_killed)
	await physics_frame
	_check(player._creature_in_front() == test_creature, "LMB targeting prioritizes the closer passive creature")
	var health_before_hit: int = int(test_creature.state.health)
	_check(player.break_target() and int(test_creature.state.health) < health_before_hit,
		"first player interaction damages a living passive creature")
	var remaining_attacks := CreatureDB.health("boar") + 1
	while remaining_attacks > 0 and is_instance_valid(test_creature) and bool(test_creature.state.get("alive", false)):
		player.break_target()
		remaining_attacks -= 1
	_check(not bool(test_creature.state.get("alive", true)), "lethal player interaction kills the creature")
	await process_frame
	_check(_game.inventory.count_of(ItemDB.RAW_MEAT) > meat_before,
		"a boar death adds species-appropriate raw meat, not an Oak Log")
	_check(_game.inventory.count_of(ItemDB.HIDE) > hide_before, "a boar death adds a hide")
	_check(_game.inventory.count_of(BlockDB.OAK_LOG) == oak_before,
		"the boar drop did not add an unrelated Oak Log (the M20 defect)")

	# Hostile creatures: contact damage, player combat and loot through the real
	# scene node and game inventory integration.
	var hostile_state := {"id": 9100, "species": "grunt",
		"position": player.global_position + Vector3(0.0, 0.0, -0.9),
		"health": HostileModel.HIT_POINTS, "alive": true, "key": "integration-grunt"}
	var test_hostile = HostileScript.new()
	test_hostile.configure(hostile_state, _game.world, player)
	# Deliberately kept out of `_game.hostile_nodes`: the daytime retire pass
	# would free it.  The signals and the player's creature ray do not need it.
	test_hostile.set_physics_process(false)
	_game.hostile_root.add_child(test_hostile)
	test_hostile.killed.connect(_game._on_hostile_killed)
	test_hostile.attacked_player.connect(_game._on_hostile_attacked_player)
	var health_before: float = _game.health.health
	test_hostile.set_physics_process(true)
	for i in range(12):
		await physics_frame
	test_hostile.set_physics_process(false)
	_check(_game.health.health < health_before,
		"an adjacent hostile grunt deals contact damage (%.1f -> %.1f)" % [health_before, _game.health.health])
	player.flying = true
	player.teleport_to(test_hostile.global_position + Vector3(0.0, 3.0, 0.0))
	player.look_yaw(0.0)
	player.look_pitch(-89.0)
	for i in range(2):
		await physics_frame
	_check(player._creature_in_front() == test_hostile, "LMB targeting prioritizes a hostile creature")
	# The starter kit fills the hotbar, so free a slot before collecting loot.
	_game.inventory.slots[0] = BlockDB.AIR
	_game.inventory.counts[0] = 0
	var bone_before: int = _game.inventory.count_of(ItemDB.BONE)
	for i in range(CreatureDB.health("grunt")):
		player.break_target()
	await process_frame
	_check(not is_instance_valid(test_hostile), "player hits kill the hostile grunt")
	_check(_game.inventory.count_of(ItemDB.BONE) > bone_before,
		"a hostile death adds species-appropriate bone loot")

	# The night clock drives the game's own spawner (not just the model).
	_game.clock.set_time(0.75)
	for i in range(3):
		_game._update_hostiles(2.0)
	_check(_game.hostile_nodes.size() > 0, "the night clock spawns hostiles through the game")
	for key: Variant in _game.hostile_nodes.keys():
		var spawned: Node = _game.hostile_nodes[key]
		if is_instance_valid(spawned):
			spawned.queue_free()
	_game.hostile_nodes.clear()
	_game.hostile_model.states.clear()
	_game.clock.set_time(0.25)
	await process_frame

	# Put the player back where the movement tests expect it.
	player.teleport_to(landed)
	player.look_yaw(0.0)
	player.look_pitch(-70.0)

	# The loot tests may have left a material in the selected slot.  A material is
	# never placeable, and the build checks below need a block selected.
	_game.inventory.select(0)
	_check(not ItemDB.is_block(_game.inventory.selected_item()),
		"a material (or empty slot) is not a placeable item")
	_check(not player.place_selected(), "place_selected() refuses to place a non-block item")
	var block_slot := -1
	for index in Inventory.HOTBAR_SIZE:
		if ItemDB.is_block(_game.inventory.slots[index]):
			block_slot = index
			break
	_check(block_slot >= 0, "the hotbar still holds a placeable block")
	_game.inventory.select(block_slot)
	_check(ItemDB.is_block(_game.inventory.selected_item()), "a block is selected for the build checks")
	# Keep directional-input checks on a wide, level surface so generated
	# mountain faces cannot turn a movement regression into an accidental wall test.
	_prepare_test_pad(Vector2i(roundi(landed.x), roundi(landed.z)), 16)
	await _stream_until_settled()
	player.flying = true
	player.teleport_to(Vector3(landed.x, float(_test_pad_y + 5), landed.z))
	player.look_yaw(0.0)
	player.look_pitch(-70.0)

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

	# Pausing must stop the body; movement resumes afterwards.
	_game._pause()
	await process_frame
	await process_frame
	var paused_before: Vector3 = player.global_position
	Input.action_press("move_forward")
	for i in range(30):
		await physics_frame
	Input.action_release("move_forward")
	var paused_distance := Vector2(player.global_position.x - paused_before.x, player.global_position.z - paused_before.z).length()
	_check(paused_distance < 0.05, "the player does not move while the game is paused (%.3f units)" % paused_distance)
	_check(not player.is_physics_processing(), "pause disables the player's physics")
	_game._resume()
	_check(player.is_physics_processing(), "resume enables the player's physics")
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
	_prepare_test_pad()
	await _stream_until_settled()
	player.flying = true
	player.teleport_to(Vector3(8.5, float(_test_pad_y + 5), 8.5))
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
	# neighbouring chunk in.  A level pad keeps the walk clear of generated trees
	# and slopes on either side of the boundary.
	_prepare_test_pad(Vector2i(14, 8), 6)
	await _stream_until_settled()
	player.teleport_to(Vector3(14.5, float(_test_pad_y) + 2.0, 8.5))
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

	# --- Block edits through the real streamer and collision world ---------
	# 1) Breaking a fully enclosed block must expose six faces in the live mesh
	#    and collision, with the authoritative voxel gone.
	var settled_seconds := await _stream_until_settled()
	_check(settled_seconds >= 0, "the streamer settles before the edit regressions")
	var interior := _find_enclosed_cell()
	_check(interior.x != -999, "found an enclosed solid block in the streamed world")
	if interior.x != -999:
		var interior_coord := VoxelWorld.world_to_chunk(interior)
		var streamer: ChunkStreamer = _game.streamer
		var faces_before := int(streamer.face_counts.get(interior_coord, -1))
		_game.world.set_block(interior, BlockDB.AIR)
		await _stream_until_settled()
		var fresh := ChunkMesher.new(_game.library, _game.materials).build(
			_game.world.get_chunk(interior_coord), _game.world)
		_check(_game.world.get_block(interior) == BlockDB.AIR,
			"the authoritative block data records the interior break")
		_check(int(streamer.face_counts.get(interior_coord, -1)) == int(fresh["faces"]),
			"the live interior chunk mesh matches a fresh build from the voxels")
		_check(int(fresh["faces"]) == faces_before + 6,
			"the interior break adds exactly the six newly exposed faces")
		var interior_view: Node3D = streamer.views.get(interior_coord)
		var local_centre := _face_centre(interior, Vector3i.RIGHT) - Vector3(VoxelWorld.chunk_origin(interior_coord))
		var interior_mesh: MeshInstance3D = null
		if interior_view != null:
			interior_mesh = interior_view.get_node_or_null("Solid") as MeshInstance3D
		_check(interior_mesh != null and _mesh_has_face(interior_mesh.mesh, local_centre, Vector3.LEFT),
			"the live interior mesh contains the +X neighbour's exposed face")
		var interior_collision := _collision_shape_faces(interior_view) if interior_view != null else PackedVector3Array()
		_check(_faces_have(interior_collision, local_centre, Vector3.LEFT),
			"the live interior collision contains the +X neighbour's exposed face")
		_check(interior_collision.size() / 3 == _collision_triangle_count(fresh["collision"]),
			"the live interior collision triangle count matches the voxel build")
		var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(
			Vector3(interior) + Vector3(0.5, 0.5, 0.5),
			Vector3(interior) + Vector3(1.5, 0.5, 0.5), 1)
		query.exclude = [player.get_rid()]
		var hit: Dictionary = space.intersect_ray(query)
		var hit_position := Vector3.ZERO
		if not hit.is_empty():
			hit_position = hit["position"]
		_check(not hit.is_empty() and absf(hit_position.x - float(interior.x + 1)) < 0.02,
			"collision stops a probe through the interior hole at the remaining wall")

	# 2) Breaking a block on a +Z chunk boundary must rebuild the neighbour: its
	#    previously culled face and collision must appear, and the collision must
	#    stop a probe through the hole.
	var pair := _find_boundary_pair()
	_check(not pair.is_empty(), "found a solid pair across a +Z chunk boundary")
	if not pair.is_empty():
		var boundary_cell: Vector3i = pair["target"]
		var neighbour_coord: Vector3i = pair["neighbour"]
		var streamer: ChunkStreamer = _game.streamer
		var neighbour_faces_before := int(streamer.face_counts.get(neighbour_coord, -1))
		_game.world.set_block(boundary_cell, BlockDB.AIR)
		await _stream_until_settled()
		var fresh_neighbour := ChunkMesher.new(_game.library, _game.materials).build(
			_game.world.get_chunk(neighbour_coord), _game.world)
		_check(_game.world.get_block(boundary_cell) == BlockDB.AIR,
			"the authoritative block data records the +Z boundary break")
		_check(int(streamer.face_counts.get(neighbour_coord, -1)) == int(fresh_neighbour["faces"]),
			"the neighbouring chunk's live mesh matches a fresh build from the voxels")
		_check(int(streamer.face_counts.get(neighbour_coord, -1)) == neighbour_faces_before + 1,
			"the +Z neighbour rebuilt the newly exposed boundary face")
		var neighbour_view: Node3D = streamer.views.get(neighbour_coord)
		var shared_centre := _face_centre(boundary_cell, Vector3i.BACK) - Vector3(VoxelWorld.chunk_origin(neighbour_coord))
		var neighbour_mesh: MeshInstance3D = null
		if neighbour_view != null:
			neighbour_mesh = neighbour_view.get_node_or_null("Solid") as MeshInstance3D
		_check(neighbour_mesh != null and _mesh_has_face(neighbour_mesh.mesh, shared_centre, Vector3.FORWARD),
			"the live +Z neighbour mesh contains the exposed boundary face")
		var neighbour_collision := _collision_shape_faces(neighbour_view) if neighbour_view != null else PackedVector3Array()
		_check(_faces_have(neighbour_collision, shared_centre, Vector3.FORWARD),
			"the live +Z neighbour collision contains the exposed boundary face")
		_check(neighbour_collision.size() / 3 == _collision_triangle_count(fresh_neighbour["collision"]),
			"the live +Z neighbour collision triangle count matches the voxel build")
		var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(
			Vector3(boundary_cell) + Vector3(0.5, 0.5, 0.5),
			Vector3(boundary_cell) + Vector3(0.5, 0.5, 1.5), 1)
		query.exclude = [player.get_rid()]
		var hit: Dictionary = space.intersect_ray(query)
		var hit_position := Vector3.ZERO
		if not hit.is_empty():
			hit_position = hit["position"]
		_check(not hit.is_empty() and absf(hit_position.z - float(boundary_cell.z + 1)) < 0.02,
			"collision stops a probe through the +Z boundary hole at the remaining wall")

	# Configuration panel: values apply live to the streamer and the player.
	var original_distance: int = _game.settings.render_distance
	var original_sensitivity: float = _game.settings.mouse_sensitivity
	var original_vsync: bool = _game.settings.vsync
	_game._open_settings()
	await process_frame
	_check(_game.settings_panel.is_open(), "the settings panel opens")
	_check(not player.can_interact, "the settings panel disables player interaction")
	_game._on_setting_changed("render_distance", 2)
	_check(_game.settings.render_distance == 2, "the render distance setting is stored")
	_check(_game.streamer.render_radius == 2, "the render distance applies live to the streamer")
	_game._on_setting_changed("mouse_sensitivity", 0.004)
	_check(is_equal_approx(player.mouse_sensitivity, 0.004), "the sensitivity applies live to the player")
	_game._on_setting_changed("vsync", not original_vsync)
	_check(_game.settings.vsync == (not original_vsync), "the vsync setting is stored")
	_game._on_setting_changed("render_distance", original_distance)
	_game._on_setting_changed("mouse_sensitivity", original_sensitivity)
	_game._on_setting_changed("vsync", original_vsync)
	_game._close_settings()
	await process_frame
	_check(not _game.settings_panel.is_open(), "the settings panel closes")
	_check(_game.streamer.render_radius == original_distance, "the restored render distance applies back")

	# --- Crafting through the real interface and the world station ---------
	await _crafting_and_mining_section()
	await _hunger_section()

	# --- M21 farming, cooking and persistent storage ------------------------
	await _m21_gameplay_section()

	# --- M22 bounded lantern lighting ---------------------------------------
	await _lantern_lights_section()

	# --- M23 roof stairs through the real scene -----------------------------
	await _stairs_section()

	# --- M29 slate roof pieces through the real scene ----------------------
	await _m29_section()

	# --- M40 placement ghost: real raycast, UI gate and final placement ----
	await _placement_preview_section()

	# --- Inventory interface: slots, stack moves and item details ----------
	await _inventory_section()

	# --- M40 screen: nav, grid crafting, vitals, HUD hand-off --------------
	await _m40_section()

	# --- Interactive world-object stations ---------------------------------
	await _stations_section()

	# --- Settlements and residents -----------------------------------------
	await _residents_section()

	# --- Persistence must not duplicate a cursor stack ---------------------
	await _persistence_cursor_section()

	# --- M28 final player-built village/castle survives save + reload ------
	await _final_journey_section()

	if _failures.is_empty():
		print("M17_INTEGRATION_PASS %d assertions" % _passes)
		quit(0)
	else:
		for failure: String in _failures:
			print("M17_INTEGRATION_FAILURE %s" % failure)
		print("M17_INTEGRATION_FAIL %d failures, %d passes" % [_failures.size(), _passes])
		quit(1)


## M22 lantern light pool: a lantern near the player is tracked and lit, removing
## it unregisters it, and a chunk unload removes its lanterns.  The pool is always
## bounded, so a world full of lanterns cannot create a node per lantern.
func _lantern_lights_section() -> void:
	var manager = _game.lantern_lights
	_check(manager != null, "the game owns a lantern light manager")
	if manager == null:
		return
	var world: VoxelWorld = _game.world
	var player: Node = _game.player
	var before := int(manager.stats()["tracked"])

	var cell := Vector3i(12, 74, 12)
	world.ensure_chunk(VoxelWorld.world_to_chunk(cell))
	world.set_block(cell, BlockDB.AIR)
	world.set_block(cell, BlockDB.LANTERN)
	manager.refresh()
	_check(int(manager.stats()["tracked"]) == before + 1,
		"placing a lantern registers it with the bounded light manager")
	_check(int(manager.stats()["assigned"]) >= 1, "the nearby lantern is assigned a pooled light")
	_check(manager.get_child_count() <= 12, "the lantern manager never exceeds its light pool")
	manager.set_daylight(0.0)
	var night_energy := 0.0
	if manager.get_child_count() > 0:
		night_energy = (manager.get_child(0) as OmniLight3D).light_energy
	_check(night_energy > 1.0, "the lantern light is warm and bright at night")
	manager.set_daylight(1.0)
	var day_energy := 0.0
	if manager.get_child_count() > 0:
		day_energy = (manager.get_child(0) as OmniLight3D).light_energy
	_check(day_energy < 0.2, "the lantern light fades out in daylight")

	world.set_block(cell, BlockDB.AIR)
	manager.refresh()
	_check(int(manager.stats()["tracked"]) == before,
		"removing a lantern unregisters its light")

	# A lantern in a chunk that unloads must not leave a light node behind.
	var far := Vector3i(260, 74, 260)
	world.ensure_chunk(VoxelWorld.world_to_chunk(far))
	world.set_block(far, BlockDB.LANTERN)
	manager.refresh()
	var with_far := int(manager.stats()["tracked"])
	_check(with_far == before + 1, "a far lantern is tracked while its chunk is loaded")
	world.unload_chunk(VoxelWorld.world_to_chunk(far))
	manager.refresh()
	_check(int(manager.stats()["tracked"]) == before,
		"unloading a chunk removes its lanterns from the registry")
	_check(manager.get_child_count() <= 12, "the light pool stays bounded after unload")

	# The showcase must never write into a normal save.  `_save_now` is the
	# manual path; `_save_silently` is the autosave/quit path and shares the guard.
	var save_path: String = _game.saves.save_path()
	var save_existed := FileAccess.file_exists(save_path)
	var save_time := FileAccess.get_modified_time(save_path)
	var previous_mode := str(_game._options["visual_test"])
	_game._options["visual_test"] = "normal"
	_game._save_now()
	_check(FileAccess.file_exists(save_path) == save_existed
		and FileAccess.get_modified_time(save_path) == save_time,
		"the showcase mode refuses to write a normal save")
	_game._options["visual_test"] = previous_mode


## M23 roof stairs through the real scene: the recipe is reachable, the crafted
## stair is selected and placed from the player's aim with an orientation, the
## live streamed mesh and collision match a fresh build of the same voxels, the
## stair is mined back for its drop, and a small player-built stair roof keeps its
## orientation through a chunk unload and regeneration.
func _stairs_section() -> void:
	var player: VoxelPlayer = _game.player
	var world: VoxelWorld = _game.world
	var streamer: ChunkStreamer = _game.streamer
	var inventory: Inventory = _game.inventory

	var recipe: Dictionary = Crafting.recipe("stair")
	_check(not recipe.is_empty(), "the stair recipe is in the catalogue")
	_check(int(recipe.get("output", -1)) == BlockDB.STAIR, "the stair recipe outputs the stair block")
	_check(str(recipe.get("station", "")) == Crafting.STATION_TABLE, "the stair recipe needs a crafting table")

	# A small stone platform in clear air above the terrain, near spawn; the player
	# hovers above it so the aimed face is the platform's top and the placement
	# cell is clear of the body.
	var base := Vector3i(24, 90, 24)
	world.ensure_chunk(VoxelWorld.world_to_chunk(base))
	for y in range(base.y, base.y + 6):
		world.set_block(Vector3i(base.x, y, base.z), BlockDB.AIR, false)
	for offset: Vector3i in [Vector3i(0, 0, 0), Vector3i.RIGHT, Vector3i(0, 0, 1),
			Vector3i.RIGHT + Vector3i(0, 0, 1)]:
		world.set_block(base + offset, BlockDB.STONE, false)
	var stair_cell := base + Vector3i.UP

	inventory.clear_slot(0)
	inventory.put_stack(0, {"item": BlockDB.STAIR, "count": 8})
	inventory.select(0)
	_check(inventory.selected_item() == BlockDB.STAIR, "the crafted stair is selectable from the hotbar")
	if inventory.selected_item() != BlockDB.STAIR:
		return

	player.flying = true
	player.teleport_to(Vector3(stair_cell.x + 0.5, stair_cell.y + 2.0, stair_cell.z + 0.5))
	player.look_yaw(-90.0)  # forward is +X, so the stair's low side faces +X
	player.look_pitch(-89.0)
	for i in range(3):
		await process_frame
	var aimed: Dictionary = player.target()
	var aimed_cell: Vector3i = base
	if aimed.get("hit", false):
		aimed_cell = aimed["block"]
	_check(aimed.get("hit", false) and aimed_cell == base,
		"the player aims at the platform's top face before placing")
	var count_before := inventory.count_of(BlockDB.STAIR)
	var placed: bool = player.place_selected()
	await process_frame
	_check(placed, "the player places a stair from the hotbar")
	_check(world.get_block(stair_cell) == BlockDB.STAIR, "the placed cell holds a stair")
	_check(world.get_orientation(stair_cell) == 1, "the stair faces the player's look direction")
	_check(inventory.count_of(BlockDB.STAIR) == count_before - 1, "placing the stair consumes one item")

	# The live HUD feedback names the material, the aimed face and the remaining
	# count, and R exposes an explicit rotation that the preview reflects.
	await process_frame
	var build_prompt: String = _game.hud.build_prompt_text()
	_check(build_prompt.contains("Stair") and build_prompt.contains("top")
		and build_prompt.contains("left"), "the HUD build prompt names the stair, face and count")
	player.rotate_placement()
	await process_frame
	var rotated_prompt: String = _game.hud.build_prompt_text()
	_check(rotated_prompt.contains("rotate"), "the HUD build prompt documents the stair rotation")
	_check(rotated_prompt.contains("+Z"), "the HUD build prompt shows the explicit facing")

	# The live streamed mesh and collision must be exactly what the mesher derives
	# from the same voxels, including the partial stair geometry.
	var settled := await _stream_until_settled()
	_check(settled >= 0, "the streamer settles after placing the stair")
	var stair_coord := VoxelWorld.world_to_chunk(stair_cell)
	var fresh := ChunkMesher.new(_game.library, _game.materials).build(world.get_chunk(stair_coord), world)
	_check(int(streamer.face_counts.get(stair_coord, -1)) == int(fresh["faces"]),
		"the live chunk mesh matches a fresh build after placing the stair")
	var stair_view: Node3D = streamer.views.get(stair_coord)
	var live_collision := _collision_shape_faces(stair_view)
	_check(live_collision.size() / 3 == _collision_triangle_count(fresh["collision"]),
		"the live collision matches a fresh build of the stair chunk")

	# Mine it back through the real player path: one stair in, one stair out.
	player.teleport_to(Vector3(stair_cell.x + 0.5, stair_cell.y + 2.0, stair_cell.z + 0.5))
	player.look_yaw(-90.0)
	player.look_pitch(-89.0)
	for i in range(3):
		await process_frame
	var stair_target: Dictionary = player.target()
	var stair_target_cell: Vector3i = stair_cell
	if stair_target.get("hit", false):
		stair_target_cell = stair_target["block"]
	_check(stair_target.get("hit", false) and stair_target_cell == stair_cell,
		"the player targets the placed stair")
	var before_mine := inventory.count_of(BlockDB.STAIR)
	if stair_target.get("hit", false):
		_check(player.break_target(), "the player mines the stair")
		_check(world.get_block(stair_cell) == BlockDB.AIR, "mining removes the stair")
		_check(world.get_orientation(stair_cell) == 0, "mining clears the stair orientation")
		_check(inventory.count_of(BlockDB.STAIR) == before_mine + 1, "mining returns the stair item")
	player.flying = false

	# A three-cell player-built stair roof in a far chunk keeps its block ids and
	# orientations through an unload and regeneration, the data path the streamer
	# uses when it drops and later rebuilds a chunk.
	var roof := Vector3i(260, 74, 260)
	var roof_coord := VoxelWorld.world_to_chunk(roof)
	world.ensure_chunk(roof_coord)
	for index in 3:
		world.set_block_state(roof + Vector3i(index, 0, 0), BlockDB.STAIR, index)
	world.unload_chunk(roof_coord)
	_check(not world.has_chunk(roof_coord), "the stair-roof chunk unloads")
	world.ensure_chunk(roof_coord)
	for index in 3:
		_check(world.get_block(roof + Vector3i(index, 0, 0)) == BlockDB.STAIR,
			"stair roof block %d survives unload and regeneration" % index)
		_check(world.get_orientation(roof + Vector3i(index, 0, 0)) == index,
			"stair roof orientation %d survives unload and regeneration" % index)


## M29 roof pieces through the real scene: the recipe exists, a slate roof stair
## and ridge are placed from the hotbar with their orientation, the live HUD
## prompt reports the rotation, and both are mined back for their drop.
func _m29_section() -> void:
	var player: VoxelPlayer = _game.player
	var world: VoxelWorld = _game.world
	var inventory: Inventory = _game.inventory

	var recipe: Dictionary = Crafting.recipe("slate_roof_stair")
	_check(not recipe.is_empty(), "the slate roof stair recipe is in the catalogue")
	_check(int(recipe.get("output", -1)) == BlockDB.SLATE_STAIR,
		"the roof stair recipe outputs the slate stair")
	_check(str(recipe.get("station", "")) == Crafting.STATION_TABLE,
		"the slate roof stair needs a crafting table")
	var ridge_recipe: Dictionary = Crafting.recipe("slate_ridge")
	_check(not ridge_recipe.is_empty(), "the slate ridge recipe is in the catalogue")
	_check(int(ridge_recipe.get("output", -1)) == BlockDB.SLATE_RIDGE,
		"the ridge recipe outputs the slate ridge")

	var base := Vector3i(30, 90, 30)
	world.ensure_chunk(VoxelWorld.world_to_chunk(base))
	for dz in range(2):
		for dx in range(2):
			for y in range(base.y, base.y + 6):
				world.set_block(base + Vector3i(dx, y, dz), BlockDB.AIR, false)
			world.set_block(base + Vector3i(dx, 0, dz), BlockDB.STONE, false)
	var stair_cell := base + Vector3i.UP
	inventory.clear_slot(0)
	inventory.clear_slot(1)
	inventory.clear_slot(2)
	inventory.put_stack(0, {"item": BlockDB.SLATE_STAIR, "count": 4})
	inventory.select(0)
	player.placement_facing = -1
	_check(inventory.selected_item() == BlockDB.SLATE_STAIR, "the slate roof stair is selectable")
	player.flying = true
	player.teleport_to(Vector3(stair_cell.x + 0.5, stair_cell.y + 2.0, stair_cell.z + 0.5))
	player.look_yaw(-90.0)
	player.look_pitch(-89.0)
	for i in range(3):
		await process_frame
	var aimed: Dictionary = player.target()
	_check(aimed.get("hit", false) and aimed.get("block", Vector3i.ZERO) == base,
		"the player aims at the platform before placing the slate roof stair")
	var before := inventory.count_of(BlockDB.SLATE_STAIR)
	_check(player.place_selected(), "the player places a slate roof stair from the hotbar")
	await process_frame
	_check(world.get_block(stair_cell) == BlockDB.SLATE_STAIR, "the placed cell holds a slate roof stair")
	_check(world.get_orientation(stair_cell) == 1, "the slate roof stair follows the player's look")
	_check(inventory.count_of(BlockDB.SLATE_STAIR) == before - 1, "placing consumes one slate stair item")
	var prompt: String = _game.hud.build_prompt_text()
	_check(prompt.contains("Slate Stair") and prompt.contains("rotate"),
		"the HUD prompt offers to rotate the slate roof stair")
	player.rotate_placement()
	await process_frame
	_check(_game.hud.build_prompt_text().contains("+Z"),
		"the HUD prompt shows the explicit slate stair facing")

	inventory.put_stack(2, {"item": ItemDB.STONE_PICKAXE, "count": 1, "durability": 100})
	inventory.select(2)
	player.teleport_to(Vector3(stair_cell.x + 0.5, stair_cell.y + 2.0, stair_cell.z + 0.5))
	player.look_yaw(-90.0)
	player.look_pitch(-89.0)
	for i in range(3):
		await process_frame
	var stair_target: Dictionary = player.target()
	if stair_target.get("hit", false):
		_check(player.break_target(), "the player mines the slate roof stair")
		_check(world.get_block(stair_cell) == BlockDB.AIR, "mining removes the slate roof stair")
		_check(inventory.count_of(BlockDB.SLATE_STAIR) == before, "mining returns the slate stair item")

	var ridge_cell := base + Vector3i(1, 1, 1)
	inventory.put_stack(1, {"item": BlockDB.SLATE_RIDGE, "count": 2})
	inventory.select(1)
	player.placement_facing = -1
	_check(player.rotate_placement() == 0, "R starts the ridge on its X axis")
	player.teleport_to(Vector3(ridge_cell.x + 0.5, ridge_cell.y + 2.0, ridge_cell.z + 0.5))
	player.look_yaw(-90.0)
	player.look_pitch(-89.0)
	for i in range(3):
		await process_frame
	var ridge_target: Dictionary = player.target()
	_check(ridge_target.get("hit", false), "the player aims at the platform before placing the ridge")
	_check(player.place_selected(), "the player places a slate ridge from the hotbar")
	await process_frame
	_check(world.get_block(ridge_cell) == BlockDB.SLATE_RIDGE, "the placed cell holds a slate ridge")
	_check(world.get_orientation(ridge_cell) == 0, "the slate ridge keeps its X axis")
	var ridge_prompt: String = _game.hud.build_prompt_text()
	_check(ridge_prompt.contains("long axis X"), "the HUD prompt names the ridge's long axis")
	player.rotate_placement()
	await process_frame
	_check(_game.hud.build_prompt_text().contains("long axis Z"),
		"rotating the ridge switches its long axis to Z")

	player.teleport_to(Vector3(ridge_cell.x + 0.5, ridge_cell.y + 2.0, ridge_cell.z + 0.5))
	player.look_yaw(-90.0)
	player.look_pitch(-89.0)
	inventory.select(2)
	for i in range(3):
		await process_frame
	var ridge_mine: Dictionary = player.target()
	if ridge_mine.get("hit", false):
		_check(player.break_target(), "the player mines the slate ridge")
		_check(world.get_block(ridge_cell) == BlockDB.AIR, "mining removes the slate ridge")
	player.flying = false


## M40 placement ghost through the real scene: the live voxel raycast targets a
## real cell, the ghost follows the same preview dictionary, opening an
## interface hides it and gates the placement action, and the eventual block
## lands in exactly the previewed cell with exactly the previewed orientation.
func _placement_preview_section() -> void:
	var player: VoxelPlayer = _game.player
	var world: VoxelWorld = _game.world
	var inventory: Inventory = _game.inventory
	var ghost = _game.placement_preview
	if _game.inventory_panel.is_open():
		_game.inventory_panel.close()
	player.can_interact = true
	player.flying = true
	var base := Vector3i(40, 90, 40)
	world.ensure_chunk(VoxelWorld.world_to_chunk(base))
	for dz in range(-6, 7):
		for dx in range(-4, 5):
			var x := base.x + dx
			var z := base.z + dz
			for y in range(base.y, base.y + 7):
				world.set_block(Vector3i(x, y, z), BlockDB.AIR, false)
			world.set_block(Vector3i(x, base.y, z), BlockDB.STONE, false)
	var target := Vector3i(base.x, base.y, base.z - 4)
	world.set_block(target, BlockDB.PLANKS, false)
	var destination := target + Vector3i.UP
	var feet := Vector3(base.x + 0.5, float(base.y) + 1.05, base.z + 0.5)
	player.teleport_to(feet)
	player.look_yaw(0.0)
	var eye := feet + Vector3(0.0, VoxelPlayer.EYE_HEIGHT, 0.0)
	var aim := Vector3(target) + Vector3(0.5, 1.0, 0.5)
	var delta := aim - eye
	player.look_pitch(rad_to_deg(atan2(delta.y, Vector2(delta.x, delta.z).length())))
	inventory.clear_slot(0)
	inventory.put_stack(0, {"item": BlockDB.STONE, "count": 8})
	inventory.select(0)
	player.placement_facing = -1
	streamer_focus(player.global_position)
	for i in range(4):
		await process_frame

	_check(player.target().get("hit", false) and player.target()["block"] == target,
		"the live crosshair targets the staged surface")
	var preview: Dictionary = player.placement_preview()
	_check(bool(preview.get("valid", false)), "the live preview accepts the staged face")
	_check(preview.get("cell", Vector3i.ZERO) == destination,
		"the live preview reports the exact destination cell")
	_check(ghost.is_showing(), "the ghost is visible during normal gameplay")
	_check(ghost.preview_cell() == destination,
		"the ghost's position is the preview's destination cell")
	_check(ghost.preview_block() == BlockDB.STONE,
		"the ghost uses the selected block")
	var preview_cell: Vector3i = preview["cell"]
	var preview_orientation := int(preview["orientation"])

	# An open interface must hide the ghost and swallow the placement action.
	_game._open_inventory()
	await process_frame
	_check(not ghost.is_showing(), "opening the inventory hides the placement ghost")
	var before_block := world.get_block(preview_cell)
	var place_event := InputEventAction.new()
	place_event.action = "place_block"
	place_event.pressed = true
	_game._unhandled_input(place_event)
	_check(world.get_block(preview_cell) == before_block,
		"a placement action while the inventory owns input changes nothing")
	_game._close_inventory()
	for i in range(3):
		await process_frame
	_check(player.can_interact, "closing the inventory restores interaction")
	_check(ghost.is_showing(), "closing the inventory brings the ghost back")

	# Selecting a non-placeable item hides the ghost; selecting another block
	# changes the ghost without changing the destination.
	inventory.put_stack(0, {"item": ItemDB.APPLE, "count": 2})
	for i in range(2):
		await process_frame
	_check(not ghost.is_showing(), "a held food item hides the placement ghost")
	inventory.put_stack(0, {"item": BlockDB.GLASS, "count": 4})
	for i in range(2):
		await process_frame
	_check(ghost.is_showing() and ghost.preview_block() == BlockDB.GLASS,
		"changing the selected block updates the ghost")
	inventory.put_stack(0, {"item": BlockDB.STONE, "count": 8})
	for i in range(2):
		await process_frame
	_check(ghost.preview_cell() == preview_cell, "changing items keeps the destination cell")

	# The actual transaction uses the same preview result.
	preview = player.placement_preview()
	preview_cell = preview["cell"]
	preview_orientation = int(preview["orientation"])
	_check(player.place_selected(), "the previewed block can be placed")
	_check(world.get_block(preview_cell) == BlockDB.STONE,
		"the placed block is exactly in the previewed cell")
	_check(world.get_orientation(preview_cell) == preview_orientation,
		"the placed block has exactly the previewed orientation")
	await process_frame

	player.flying = false
	player.teleport_to(Vector3(8.5, float(_test_pad_y + 1), 8.5))
	player.look_pitch(-10.0)
	streamer_focus(player.global_position)
	await process_frame


## Small helper so this section can move the streamer without knowing its field
## name in the game script.
func streamer_focus(position: Vector3) -> void:
	if _game.streamer != null:
		_game.streamer.focus_at(position)


## Crafting and mining through the real scene: the station is taken from the
## world, the panel's own Craft button drives the craft, and the mining rule
## (hardness, tool speed, tool requirement, durability) is exercised through the
## real player controller.
func _crafting_and_mining_section() -> void:
	var player: Node = _game.player
	var inventory: Inventory = _game.inventory
	# The hotbar is a fixed size and the kit fills it; free two slots so the
	# crafting ingredients and the loot below actually fit.
	inventory.clear_slot(0)
	inventory.clear_slot(1)
	player.flying = true
	player.teleport_to(Vector3(8.5, float(_test_pad_y + 5), 8.5))
	player.look_yaw(0.0)
	player.look_pitch(-89.0)
	for i in range(2):
		await process_frame

	# The station is a block in the world, not a menu flag.
	var table_cell := Vector3i(8, _test_pad_y + 1, 8)
	_check(_game.world.is_loaded(table_cell), "the station cell is loaded")
	_game.world.set_block(table_cell, BlockDB.CRAFTING_TABLE)
	var feet := Vector3i(floori(player.global_position.x), floori(player.global_position.y),
		floori(player.global_position.z))
	_check(Crafting.best_station(_game.world, feet, 4) == Crafting.STATION_TABLE,
		"a placed crafting table becomes the player's station")
	inventory.add(BlockDB.COBBLESTONE, 8)
	inventory.add(ItemDB.STICK, 4)
	_game._open_crafting()
	await process_frame
	_check(_game.crafting.is_open(), "the crafting panel opens")
	_check(not player.can_interact, "the crafting panel disables player interaction")
	_check(_game.crafting.station() == Crafting.STATION_TABLE, "the panel receives the world station")
	_check(_game.crafting.row_count() == Crafting.recipes().size(), "the panel lists every recipe")

	# The exact reported scenario: eight cobblestone, a crafting table nearby, and
	# the furnace recipe.  It must be enabled, consume exactly eight and create one.
	inventory.remove(BlockDB.COBBLESTONE, inventory.count_of(BlockDB.COBBLESTONE))
	inventory.add(BlockDB.COBBLESTONE, 8)
	var furnace_before := inventory.count_of(BlockDB.FURNACE)
	_check(_game.crafting.row_enabled("furnace"),
		"eight cobblestone unlock the furnace at a crafting table")
	_check(_game.crafting.press_craft("furnace"),
		"the catalogue's furnace Craft button activates")
	await process_frame
	_check(inventory.count_of(BlockDB.COBBLESTONE) == 0,
		"the furnace craft consumed exactly eight cobblestone")
	_check(inventory.count_of(BlockDB.FURNACE) == furnace_before + 1,
		"the furnace craft created exactly one furnace")

	inventory.add(BlockDB.COBBLESTONE, 8)
	inventory.add(ItemDB.STICK, 4)
	_check(_game.crafting.row_enabled("stone_axe"), "an affordable table recipe is enabled")
	_check(not _game.crafting.row_enabled("iron_pickaxe"), "an unaffordable station recipe stays disabled")
	_check(_game.crafting.row_status("iron_pickaxe").contains("missing"),
		"the disabled row explains the missing ingredient")
	_check(_game.crafting.row_enabled("sticks"), "a hand recipe remains craftable in the catalogue")

	var cobble_before := inventory.count_of(BlockDB.COBBLESTONE)
	var stick_before_hand := inventory.count_of(ItemDB.STICK)
	var planks_before_hand := inventory.count_of(BlockDB.PLANKS)
	_check(_game.crafting.press_craft("stone_axe"), "the catalogue crafts a station recipe")
	await process_frame
	_check(inventory.count_of(ItemDB.STONE_AXE) == 1, "the craft produced a stone axe")
	_check(inventory.count_of(BlockDB.COBBLESTONE) == cobble_before - 3,
		"the stone axe consumed exactly three cobblestone")
	var axe_slot := inventory.slots.find(ItemDB.STONE_AXE)
	_check(axe_slot >= 0 and inventory.durability_of(axe_slot) == ItemDB.max_durability(ItemDB.STONE_AXE),
		"the crafted tool arrives at full durability")

	_check(_game.crafting.press_craft("sticks"), "the catalogue crafts a hand recipe too")
	await process_frame
	_check(inventory.count_of(BlockDB.PLANKS) == planks_before_hand - 2,
		"the hand craft consumed two planks")
	_check(inventory.count_of(ItemDB.STICK) == stick_before_hand - 2 + 4,
		"the hand craft produced four sticks after the axe consumed two")

	# The batch button performs five hand crafts.
	inventory.add(BlockDB.PLANKS, 10)
	var planks_before := inventory.count_of(BlockDB.PLANKS)
	var sticks_before := inventory.count_of(ItemDB.STICK)
	_check(_game.crafting.press_craft("sticks", true), "the batch button crafts five times")
	await process_frame
	_check(inventory.count_of(BlockDB.PLANKS) == planks_before - 10,
		"the batch consumed ten planks")
	_check(inventory.count_of(ItemDB.STICK) == sticks_before + 20,
		"the batch produced twenty sticks")

	# Smelting needs the furnace station; the catalogue uses the same model.
	_check(not _game.crafting.row_enabled("iron_ingot"), "smelting needs a nearby furnace")
	_check(_game.crafting.row_status("iron_ingot").contains("Furnace"),
		"the smelting row names the missing furnace")
	_game.world.set_block(Vector3i(9, _test_pad_y + 1, 8), BlockDB.FURNACE)
	_game.crafting.set_station(_game._current_station())
	inventory.remove(ItemDB.IRON_LUMP, inventory.count_of(ItemDB.IRON_LUMP))
	inventory.remove(ItemDB.COAL, inventory.count_of(ItemDB.COAL))
	inventory.add(ItemDB.IRON_LUMP, 1)
	inventory.add(ItemDB.COAL, 1)
	_check(_game.crafting.station() == Crafting.STATION_FURNACE, "a placed furnace becomes the station")
	_check(_game.crafting.row_enabled("iron_ingot"), "the furnace unlocks smelting")
	_check(_game.crafting.press_craft("iron_ingot"), "the furnace smelts through the catalogue")
	await process_frame
	_check(inventory.count_of(ItemDB.IRON_INGOT) >= 1, "the smelted ingot is in the inventory")
	_check(inventory.count_of(ItemDB.COAL) == 0, "the smelt consumed the coal fuel")

	# Regression for "recipes requiring a crafting table do not appear": the
	# catalogue used a four-block menu radius while the interaction reach is six.
	# A table you can open with E must also unlock its recipes.
	var reach_cell := Vector3i(26, _test_pad_y + 3, 22)
	_game.world.set_block(reach_cell, BlockDB.CRAFTING_TABLE)
	player.teleport_to(Vector3(26.5, float(_test_pad_y + 5), 27.5))
	await process_frame
	_check(_game._current_station() == Crafting.STATION_TABLE,
		"a crafting table five blocks away still unlocks table recipes")
	_game.world.set_block(reach_cell, BlockDB.AIR)
	player.teleport_to(Vector3(8.5, float(_test_pad_y + 5), 8.5))
	await process_frame

	_game._close_crafting()
	await process_frame
	_check(not _game.crafting.is_open(), "the crafting panel closes")

	# --- Mining rules through the real player ------------------------------
	# A clean column so the first solid voxel below the player is the one under
	# test, whatever the terrain does nearby.
	var mine_cell := Vector3i(10, _test_pad_y + 2, 10)
	_game.world.set_block(mine_cell + Vector3i.DOWN, BlockDB.STONE)
	for clear_y in range(mine_cell.y + 1, mine_cell.y + 5):
		_game.world.set_block(Vector3i(10, clear_y, 10), BlockDB.AIR)
	_game.world.set_block(mine_cell, BlockDB.STONE)
	player.teleport_to(Vector3(mine_cell) + Vector3(0.5, 3.0, 0.5))
	player.look_yaw(0.0)
	player.look_pitch(-89.0)
	for i in range(2):
		await process_frame
	var target: Dictionary = player.target()
	_check(target.get("hit", false) and Vector3i(target["block"]) == mine_cell,
		"the stone block above the player is targeted")
	# A bare hand cannot remove stone at all (the reported defect: the block used
	# to disappear for no reward).  The requirement is checked before progress.
	var block_slot := inventory.slots.find(BlockDB.STONE)
	inventory.select(block_slot)
	var harvest_failed := [false]
	player.harvest_failed.connect(func(_block_id: int, _tool: int) -> void: harvest_failed[0] = true)
	var cobble_from_hand := inventory.count_of(BlockDB.COBBLESTONE)
	player.mine_step(0.1)
	_check(is_equal_approx(player.mining_ratio(), 0.0),
		"a bare hand makes no mining progress on stone")
	_check(int(_game.world.get_block(mine_cell)) != BlockDB.AIR,
		"a tenth of a second does not break stone by hand")
	var hand_seconds := ItemDB.break_seconds(BlockDB.STONE, BlockDB.AIR)
	var step_limit := int(hand_seconds * 10.0) + 10
	for step in step_limit:
		player.mine_step(0.1)
	_check(int(_game.world.get_block(mine_cell)) == BlockDB.STONE,
		"holding the mine action with a bare hand never breaks stone")
	_check(harvest_failed[0], "a bare hand is told stone needs a pickaxe")
	_check(inventory.count_of(BlockDB.COBBLESTONE) == cobble_from_hand,
		"a bare hand gets no drop from stone")
	# The exact reported example: coal ore is not destroyed by a bare hand.
	_game.world.set_block(mine_cell, BlockDB.COAL_ORE)
	for i in range(2):
		await process_frame
	_check(not player.break_target(), "coal ore refuses a bare-handed break")
	_check(int(_game.world.get_block(mine_cell)) == BlockDB.COAL_ORE,
		"the bare-handed coal ore remains in the world")

	# A pickaxe is faster, yields the drop and wears out.
	_check(ItemDB.break_seconds(BlockDB.STONE, ItemDB.WOOD_PICKAXE) < hand_seconds,
		"a pickaxe breaks stone faster than a bare hand")
	inventory.clear_slot(7)
	inventory.clear_slot(8)
	inventory.add(ItemDB.WOOD_PICKAXE, 1, 2)
	var pick_slot := inventory.slots.find(ItemDB.WOOD_PICKAXE)
	_check(pick_slot >= 0, "the pickaxe was added to the hotbar")
	inventory.select(pick_slot)
	var tool_broken := [false]
	player.tool_broken.connect(func(_item: int) -> void: tool_broken[0] = true)
	var drops_before := inventory.count_of(BlockDB.COBBLESTONE)
	var steps := 0
	for use in 2:
		_game.world.set_block(mine_cell, BlockDB.STONE)
		for i in range(2):
			await process_frame
		player.mine_step(0.1)
		steps = 0
		while int(_game.world.get_block(mine_cell)) != BlockDB.AIR and steps < 40:
			player.mine_step(0.1)
			steps += 1
		_check(int(_game.world.get_block(mine_cell)) == BlockDB.AIR,
			"the pickaxe breaks the stone (use %d)" % (use + 1))
	_check(inventory.count_of(BlockDB.COBBLESTONE) == drops_before + 2,
		"each pickaxe use produced its stone drop")
	_check(tool_broken[0], "the wooden pickaxe breaks after its last use")
	_check(inventory.is_empty(pick_slot), "the broken tool freed its slot")

	# A wooden pickaxe is not enough for iron: the ore cannot be broken at all.
	inventory.clear_slot(1)
	inventory.add(ItemDB.WOOD_PICKAXE, 1)
	var wood_iron_slot: int = inventory.slots.find(ItemDB.WOOD_PICKAXE)
	_check(wood_iron_slot >= 0 and wood_iron_slot < Inventory.HOTBAR_SIZE,
		"the insufficient pickaxe is in the hotbar")
	inventory.select(wood_iron_slot)
	var iron_before_wrong: int = inventory.count_of(ItemDB.IRON_LUMP)
	_game.world.set_block(mine_cell, BlockDB.IRON_ORE)
	for i in range(2):
		await process_frame
	_check(not player.break_target(), "iron ore refuses to break with an insufficient pickaxe")
	_check(inventory.count_of(ItemDB.IRON_LUMP) == iron_before_wrong,
		"a wooden pickaxe does not yield iron ore")
	_check(int(_game.world.get_block(mine_cell)) == BlockDB.IRON_ORE,
		"the wrong-tier ore block stays in the world")

	# Regression for the reported "mining iron does not appear" defect: the
	# starter kit used to fill all nine slots, so the lump had nowhere to go.  The
	# real controller, drop rule and inventory now carry it through end to end.
	inventory.clear_slot(0)
	inventory.add(ItemDB.STONE_PICKAXE, 1)
	var stone_pick_slot: int = inventory.slots.find(ItemDB.STONE_PICKAXE)
	_check(stone_pick_slot >= 0 and stone_pick_slot < Inventory.HOTBAR_SIZE,
		"a stone pickaxe is in the hotbar for the iron test")
	inventory.select(stone_pick_slot)
	var iron_before := inventory.count_of(ItemDB.IRON_LUMP)
	_game.world.set_block(mine_cell, BlockDB.IRON_ORE)
	for i in range(2):
		await process_frame
	_check(player.break_target(), "iron ore is mined through the real controller")
	_check(inventory.count_of(ItemDB.IRON_LUMP) == iron_before + 1,
		"the mined iron lump reached the inventory")
	_check(inventory.item_at(inventory.slots.find(ItemDB.IRON_LUMP)) == ItemDB.IRON_LUMP,
		"the iron lump is stored in a real slot")
	_check(int(_game.world.get_block(mine_cell)) == BlockDB.AIR, "the iron ore block was removed")

	# A common resource takes the same shared drop/pickup path.
	var coal_before := inventory.count_of(ItemDB.COAL)
	_game.world.set_block(mine_cell, BlockDB.COAL_ORE)
	for i in range(2):
		await process_frame
	_check(player.break_target(), "coal ore is mined with the same controller path")
	_check(inventory.count_of(ItemDB.COAL) == coal_before + 1,
		"the mined coal reached the inventory")

	# The UI must show the authoritative count: the HUD hotbar badge and the
	# inventory-panel badge both read the same model slot that mining updated.
	var ui_cobble_slot: int = inventory.slots.find(BlockDB.COBBLESTONE)
	if ui_cobble_slot >= Inventory.HOTBAR_SIZE:
		ui_cobble_slot = -1
	_check(ui_cobble_slot >= 0, "cobblestone is in a hotbar slot for the UI count check")
	if ui_cobble_slot >= 0:
		var ui_model_count := inventory.count_at(ui_cobble_slot)
		var ui_expected := "" if ui_model_count <= 1 else str(ui_model_count)
		_game.hud.refresh()
		_check(_game.hud.hotbar_count_text(ui_cobble_slot) == ui_expected,
			"the HUD hotbar badge matches the mined cobblestone count")
		_game._open_inventory()
		await process_frame
		_check(_game.inventory_panel.slot_count_text(ui_cobble_slot) == ui_expected,
			"the inventory panel badge matches the mined cobblestone count")
		_game._close_inventory()
		await process_frame

	player.look_pitch(0.0)
	player.teleport_to(Vector3(8.5, float(_test_pad_y + 5), 8.5))
	for i in range(2):
		await process_frame


## Hunger and eating through the real game: the drain is driven by the game's own
## survival step, eating is the real right-click path, starvation respects its
## health floor and a fed body regenerates.
func _hunger_section() -> void:
	var player: Node = _game.player
	var inventory: Inventory = _game.inventory
	player.flying = true
	player.teleport_to(Vector3(8.5, float(_test_pad_y + 5), 8.5))
	for i in range(2):
		await process_frame

	_check(is_equal_approx(_game.hunger, Survival.MAX_HUNGER) or _game.hunger <= Survival.MAX_HUNGER,
		"the game tracks a hunger value within range")
	_check(_game.hud.hunger_text().begins_with("HUNGER"),
		"the HUD shows a hunger readout (%s)" % _game.hud.hunger_text())

	# Eating at full hunger is refused rather than wasting the item.
	inventory.clear_slot(0)
	_check(inventory.add(ItemDB.APPLE, 3) == 0, "apples fit in the freed slot")
	var apple_slot := inventory.slots.find(ItemDB.APPLE)
	inventory.select(apple_slot)
	_game.hunger = Survival.MAX_HUNGER
	var apples_before := inventory.count_of(ItemDB.APPLE)
	_check(player.place_selected(), "right-click with food in hand is handled")
	_check(inventory.count_of(ItemDB.APPLE) == apples_before, "a full body refuses to waste the food")

	# Eating while hungry works through the real player path.
	_game.hunger = 8.0
	_check(player.place_selected(), "right-click eats while hungry")
	_check(inventory.count_of(ItemDB.APPLE) == apples_before - 1, "the eaten apple was consumed")
	_check(is_equal_approx(_game.hunger, 12.0), "the apple restored four hunger points")

	# The golden apple heals as well, and refills hunger.
	inventory.clear_slot(0)
	inventory.add(ItemDB.GOLDEN_APPLE, 1)
	inventory.select(0)
	_game.hunger = 2.0
	_game.health.set_health(10.0)
	var healed_before: float = _game.health.health
	_check(player.place_selected(), "the golden apple is eaten")
	_check(_game.hunger >= 12.0, "the golden apple restores ten hunger points (%.1f)" % _game.hunger)
	_check(_game.health.health > healed_before, "the golden apple heals the player")

	# Starvation drains health but never takes the last point.
	_game.hunger = 0.0
	_game.health.set_health(6.0)
	_game._seconds_since_damage = 0.0
	for i in range(400):
		await process_frame
		if _game.health.health <= Survival.STARVE_HEALTH_FLOOR + 0.01:
			break
	_check(_game.health.health < 6.0, "an empty hunger bar starves the player")
	_check(_game.health.health >= Survival.STARVE_HEALTH_FLOOR - 0.001,
		"starvation stops at its health floor (%.2f)" % _game.health.health)
	_check(not _game.health.is_dead(), "starvation does not kill the player")

	# Feeding the body restores health again after the regeneration delay.
	_game.hunger = Survival.MAX_HUNGER
	_game._seconds_since_damage = Survival.REGEN_DELAY_SECONDS + 0.1
	var before_regen: float = _game.health.health
	_game._update_survival(1.0)
	_check(_game.health.health > before_regen, "a fed body regenerates again")
	_check(_game.exhaustion >= 0.0, "regeneration accounted for its hunger cost")

	_game.health.set_health(_game.health.max_health)
	_game.hunger = Survival.MAX_HUNGER
	_game.exhaustion = 0.0
	player.flying = false


## The inventory interface through the real scene: it opens, the mouse and
## interaction follow it, stacks move between slots through the panel's own
## handlers, and the item facts pane explains what is selected.
func _inventory_section() -> void:
	var player: Node = _game.player
	var inventory: Inventory = _game.inventory
	var panel: InventoryPanel = _game.inventory_panel
	# Hotbar selection through the real input path: number key and mouse wheel.
	inventory.select(0)
	var slot_event := InputEventAction.new()
	slot_event.action = "slot_4"
	slot_event.pressed = true
	_game._unhandled_input(slot_event)
	_check(inventory.selected == 3, "number key 4 selects the fourth hotbar slot")
	var wheel_event := InputEventMouseButton.new()
	wheel_event.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel_event.pressed = true
	_game._unhandled_input(wheel_event)
	_check(inventory.selected == 4, "mouse wheel down advances the hotbar selection")
	wheel_event = InputEventMouseButton.new()
	wheel_event.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_event.pressed = true
	_game._unhandled_input(wheel_event)
	_check(inventory.selected == 3, "mouse wheel up moves the hotbar selection back")
	_game._open_inventory()
	await process_frame
	_check(panel.is_open(), "the inventory panel opens")
	_check(not player.can_interact, "the inventory panel disables player interaction")
	_check(panel.slot_count() == Inventory.SIZE, "the panel shows the 27 storage slots and the hotbar")

	# Move a stack between two slots through the panel's click path.
	inventory.clear_slot(0)
	inventory.clear_slot(4)
	_check(inventory.put_stack(0, {"item": BlockDB.GRAVEL, "count": 12, "durability": 0}).is_empty(),
		"the first slot holds gravel for the move test")
	_check(inventory.slots[0] == BlockDB.GRAVEL, "the first slot holds the gravel stack")
	_check(panel.pick_up(0), "clicking a slot picks the stack up")
	_check(inventory.is_empty(0), "the picked-up stack left its slot")
	_check(int(panel.carried().get("count", 0)) == 12, "the carried stack kept its count")
	_check(not panel.pick_up(1), "a second pick-up is refused while a stack is carried")
	_check(panel.put_down(4), "clicking another slot drops the carried stack there")
	_check(int(inventory.count_of(BlockDB.GRAVEL)) == 12, "the items survived the move")
	_check(inventory.slots[4] == BlockDB.GRAVEL and inventory.counts[4] == 12,
		"the stack arrived in the destination slot")
	_check(panel.carried().is_empty(), "nothing is left carried after a complete drop")

	# The drag & drop path calls the same model move.
	var moved := panel.swap(4, 5)
	_check(moved, "the panel can swap two slots (the drag & drop drop handler)")
	_check(inventory.slots[5] == BlockDB.GRAVEL, "the swap moved the gravel stack")

	# A tool keeps its durability through a move and is described in the panel.
	inventory.clear_slot(6)
	inventory.clear_slot(7)
	inventory.put_stack(6, {"item": ItemDB.IRON_PICKAXE, "count": 1, "durability": 100})
	panel.focus_slot(6)
	_check(panel.detail_text().contains("Iron Pickaxe"), "the detail pane names the selected tool")
	_check(panel.detail_text().contains("Durability"), "the detail pane reports tool durability")
	_check(panel.detail_text().contains("Mining speed"), "the detail pane reports the mining speed")
	_check(panel.pick_up(6), "the tool can be picked up")
	_check(panel.put_down(7), "the tool can be put down")
	_check(inventory.slots[7] == ItemDB.IRON_PICKAXE, "the tool arrived in the new slot")
	_check(inventory.durability_of(7) == 100, "the moved tool kept its durability")
	_check(not ItemDB.is_tool_item(BlockDB.STONE), "a block is still not a tool")

	# A block's detail pane reports its drop and what it is used in.
	inventory.clear_slot(8)
	inventory.put_stack(8, {"item": BlockDB.OAK_LOG, "count": 3, "durability": 0})
	panel.focus_slot(8)
	_check(panel.detail_text().contains("Oak Log"), "the detail pane names the selected block")
	_check(panel.detail_text().contains("Used in"), "the detail pane lists the recipes that use it")
	_check(panel.find_children("*Carry*", "", true, false).is_empty(),
		"the interface has no permanent carrying slot")
	var slot_with_item := panel.find_child("Slot5", true, false) as InventorySlot
	_check(slot_with_item != null and not slot_with_item.tooltip_text.is_empty(),
		"an occupied slot carries a tooltip with its name")

	# Right-click split, merge, swap and quick-move through the panel handlers.
	inventory.clear_slot(20)
	inventory.put_stack(20, {"item": BlockDB.STONE, "count": 10, "durability": 0})
	_check(panel.split_half(20), "right-click splits a stack in half")
	_check(int(panel.carried().get("count", 0)) == 5, "the split took half the stack")
	_check(inventory.count_at(20) == 5, "the other half stayed in the slot")
	_check(panel.put_down(21), "the split stack can be placed in an empty slot")
	_check(inventory.count_at(21) == 5 and inventory.count_at(20) == 5,
		"both halves survived the split and drop")

	inventory.clear_slot(22)
	inventory.clear_slot(23)
	inventory.put_stack(22, {"item": BlockDB.STONE, "count": 60, "durability": 0})
	inventory.put_stack(23, {"item": BlockDB.STONE, "count": 10, "durability": 0})
	_check(panel.pick_up(23), "the merge source can be picked up")
	_check(panel.put_down(22), "left-click merges onto a matching stack")
	_check(not panel.carried().is_empty(), "the merge leaves the overflow on the cursor")
	_check(panel.put_down(23), "the merge remainder can be put back in its source slot")
	_check(inventory.count_at(22) == 64 and inventory.count_at(23) == 6,
		"the merge filled to the stack cap and left the remainder")
	_check(inventory.count_of(BlockDB.STONE) >= 80, "the merge conserved every stone item")
	_check(panel.carried().is_empty(), "nothing is carried after a merge")

	inventory.clear_slot(24)
	inventory.clear_slot(25)
	inventory.put_stack(24, {"item": BlockDB.DIRT, "count": 3, "durability": 0})
	inventory.put_stack(25, {"item": BlockDB.SAND, "count": 7, "durability": 0})
	_check(panel.pick_up(24), "the swap source can be picked up")
	_check(panel.put_down(25), "left-click swaps with an occupied incompatible slot")
	_check(inventory.slots[25] == BlockDB.DIRT and int(panel.carried().get("item", -1)) == BlockDB.SAND,
		"the displaced stack became the cursor stack")
	_check(panel.put_down(24), "the displaced stack can be placed back")
	_check(inventory.slots[24] == BlockDB.SAND and inventory.slots[25] == BlockDB.DIRT,
		"both stacks survived the swap")

	inventory.clear_slot(2)
	inventory.put_stack(2, {"item": BlockDB.GRAVEL, "count": 5, "durability": 0})
	var gravel_before_quick := inventory.count_of(BlockDB.GRAVEL)
	_check(panel.quick_move(2), "shift-click quick-moves a hotbar stack into storage")
	_check(inventory.is_empty(2), "the hotbar source slot is empty")
	_check(inventory.count_of(BlockDB.GRAVEL) == gravel_before_quick,
		"quick-move conserved every gravel item")
	var gravel_main_slot := -1
	for index in range(Inventory.MAIN_FIRST, Inventory.SIZE):
		if inventory.item_at(index) == BlockDB.GRAVEL:
			gravel_main_slot = index
			break
	_check(gravel_main_slot >= 0, "the quick-moved gravel is in a storage slot")
	_check(panel.quick_move(gravel_main_slot), "shift-click moves a storage stack back to the hotbar")
	_check(inventory.is_empty(gravel_main_slot), "the storage source slot is empty")
	_check(inventory.count_of(BlockDB.GRAVEL) == gravel_before_quick,
		"the return quick-move conserved every gravel item")

	# Closing with a carried stack must never lose it.  First use the original
	# slot when it is still free.
	var logs_before := inventory.count_of(BlockDB.OAK_LOG)
	_check(panel.pick_up(8), "a stack can be carried when the panel closes")
	panel.close()
	await process_frame
	_check(not panel.is_open(), "the inventory panel closes")
	_check(inventory.count_of(BlockDB.OAK_LOG) == logs_before, "closing with a carried stack puts it back")
	_check(inventory.item_at(8) == BlockDB.OAK_LOG, "the stack returned to its original slot")

	# Then the fallback path: occupy the origin before closing.
	inventory.clear_slot(26)
	inventory.put_stack(26, {"item": ItemDB.IRON_INGOT, "count": 4, "durability": 0})
	var ingots_before_close := inventory.count_of(ItemDB.IRON_INGOT)
	_game._open_inventory()
	await process_frame
	_check(panel.pick_up(26), "a second stack is picked up for the recovery test")
	inventory.put_stack(26, {"item": BlockDB.DIRT, "count": 64, "durability": 0})
	var closed_with_fallback: bool = panel.close()
	await process_frame
	_check(closed_with_fallback and not panel.is_open(), "the panel closes when the origin is occupied")
	_check(inventory.count_of(ItemDB.IRON_INGOT) == ingots_before_close,
		"the fallback recovery found another slot instead of deleting the stack")
	_check(inventory.item_at(26) == BlockDB.DIRT, "the occupied origin was not overwritten")

	# Opening and closing an interface never changes the selected hotbar slot.
	inventory.select(3)
	_game._open_inventory()
	await process_frame
	_check(inventory.selected == 3, "opening the inventory leaves the selected slot alone")
	_game._close_inventory()
	await process_frame
	_check(inventory.selected == 3, "closing the inventory leaves the selected slot alone")
	_check(player.can_interact, "closing the inventory restores world interaction")


## M40 screen in the real scene: the overlay opens over the game, the HUD yields,
## the 3x3 grid crafts through the real catalogue, the character page and
## navigation switch, and closing restores the HUD, interaction and an empty
## transient grid.  This is the runtime counterpart to the unit suite.
func _m40_section() -> void:
	var player: Node = _game.player
	var inventory: Inventory = _game.inventory
	var panel: InventoryPanel = _game.inventory_panel
	_game._open_inventory()
	await process_frame
	_check(panel.is_open(), "the M40 screen opens in the real scene")
	_check(panel.page() == InventoryPanel.PAGE_INVENTORY,
		"the I key opens the Inventory page")
	_check(not _game.hud.visible, "the gameplay HUD yields to the M40 screen")
	_check(not panel.nav_enabled("map"), "the Map tab is explicitly unavailable")
	_check(panel.nav_enabled("character"), "the Character tab is available")
	_check(panel.nav_enabled("crafting"), "the Crafting tab is available")
	_check(not panel.equipment_enabled(),
		"equipment stays disabled because the game has no equipment system")
	_check(panel.vitals_text().contains("Health"), "the screen shows the live health value")
	_check(panel.vitals_text().contains("Hunger"), "the screen shows the live hunger value")
	_check(not panel.vitals_text().to_lower().contains("xp"),
		"the screen never invents an experience value")
	_check(panel.slot_count() == Inventory.SIZE,
		"the runtime screen still exposes exactly the 27+9 player slots")

	# The reported preview-scaling regression: select stacks, change pages and
	# select a recipe without changing the preview rect.
	var preview_rect := panel.character_preview_rect()
	_check(preview_rect.size.x > 0.0 and preview_rect.size.y > 0.0,
		"the runtime preview has a real rect")
	panel.focus_slot(9)
	await process_frame
	_check(panel.character_preview_rect() == preview_rect,
		"focusing an inventory slot leaves the preview rect stable")
	panel.open_context_menu(9)
	await process_frame
	_check(panel.character_preview_rect() == preview_rect,
		"opening item actions leaves the preview rect stable")
	panel.close_context_menu()

	# Polled WASD is a separate input path from `_unhandled_input`.  The player
	# must not walk behind the open screen.
	player.flying = false
	player.velocity = Vector3.ZERO
	Input.action_press("move_forward")
	await physics_frame
	await physics_frame
	_check(Vector2(player.velocity.x, player.velocity.z).length() < 0.05,
		"WASD movement is inert while the M40 screen is open")
	Input.action_release("move_forward")
	player.velocity = Vector3.ZERO

	# Character and Crafting are distinct pages.
	panel.press_nav("character")
	await process_frame
	_check(panel.page() == InventoryPanel.PAGE_CHARACTER,
		"the Character tab opens the Character page")
	_check(panel.stats_text().contains("Health") or panel.stats_text().contains("Attack"),
		"the Character page shows real stats")
	_check(panel.character_preview_rect() == preview_rect,
		"the Character page keeps the preview rect stable (%s -> %s)" % [
			preview_rect, panel.character_preview_rect()])
	panel.press_nav("crafting")
	await process_frame
	_check(panel.page() == InventoryPanel.PAGE_CRAFTING,
		"the Crafting tab opens the Crafting page")
	_check(not _game.crafting.is_open(),
		"the Crafting tab does not open the legacy crafting overlay")
	_check(not panel.character_preview_visible(),
		"the preview is hidden on the Crafting page")

	# A real transaction through the redesigned crafting page.
	var free: int = inventory.slots.find(BlockDB.AIR)
	_check(free >= 0, "the runtime inventory has a free slot for the crafting check")
	if free >= 0:
		inventory.put_stack(free, {"item": BlockDB.PLANKS, "count": 2})
		var planks_before := inventory.count_of(BlockDB.PLANKS)
		var sticks_before := inventory.count_of(ItemDB.STICK)
		panel.set_station(Crafting.STATION_HAND)
		_check(panel.select_recipe("sticks"), "the runtime recipe browser selects sticks")
		panel.set_craft_quantity(1)
		_check(panel.craft_selected(), "the runtime recipe browser crafts sticks")
		_check(inventory.count_of(BlockDB.PLANKS) == planks_before - 2,
			"the runtime craft consumed exactly two planks")
		_check(inventory.count_of(ItemDB.STICK) == sticks_before + 4,
			"the runtime craft produced four sticks")

	# The amount dialog works in the real scene, without duplication.
	free = inventory.slots.find(BlockDB.AIR)
	if free >= 0:
		inventory.put_stack(free, {"item": BlockDB.STONE, "count": 10})
		var stone_total := inventory.count_of(BlockDB.STONE)
		panel.set_page(InventoryPanel.PAGE_INVENTORY)
		_check(panel.open_amount_dialog(free) == 10, "the amount dialog opens on the slot")
		panel.set_amount_value(3)
		_check(panel.confirm_amount(), "the amount dialog confirms three stones")
		_check(int(panel.carried().get("count", 0)) == 3, "three stones are carried")
		panel.flush_cursor()
		_check(inventory.count_of(BlockDB.STONE) == stone_total,
			"the amount dialog conserved every stone")

	# R is the explicit quantity shortcut while the screen owns the mouse.
	if free >= 0:
		panel.focus_slot(9)
		var r_event := InputEventAction.new()
		r_event.action = "rotate_placement"
		r_event.pressed = true
		_game._unhandled_input(r_event)
		_check(panel.amount_dialog_open(), "R opens the amount dialog in the real scene")
		panel.cancel_amount()

	panel.press_nav("inventory")
	await process_frame
	_check(panel.page() == InventoryPanel.PAGE_INVENTORY, "the Inventory page returns")
	_check(panel.character_preview_rect() == preview_rect,
		"returning to Inventory keeps the preview rect stable (%s -> %s)" % [
			preview_rect, panel.character_preview_rect()])

	_game._close_inventory()
	await process_frame
	_check(not panel.is_open(), "the M40 screen closes")
	_check(_game.hud.visible, "the gameplay HUD returns after closing")
	_check(player.can_interact, "closing the M40 screen restores interaction")

	# Movement comes back after closing.
	player.flying = false
	player.teleport_to(Vector3(8.5, float(_test_pad_y + 1), 8.5))
	player.look_pitch(-10.0)
	player.velocity = Vector3.ZERO
	await physics_frame
	Input.action_press("move_forward")
	await physics_frame
	await physics_frame
	_check(Vector2(player.velocity.x, player.velocity.z).length() > 0.1,
		"WASD movement returns after closing the M40 screen")
	Input.action_release("move_forward")
	player.velocity = Vector3.ZERO
	player.teleport_to(Vector3(8.5, float(_test_pad_y + 1), 8.5))
	await physics_frame

	_game._open_inventory()
	await process_frame
	_check(panel.is_open(), "the M40 screen reopens")
	_check(panel.page() == InventoryPanel.PAGE_INVENTORY, "reopening starts on Inventory")
	_check(panel.character_preview_rect() == preview_rect,
		"reopening keeps the preview rect stable")
	_game._close_inventory()
	await process_frame


## Settlement residents through the real scene: a settlement's resident gets a
## node, the model's work loop runs against the live world, the player can target
## and kill a resident, and the store and resident state survive a save round-trip.
##
## The "settlement" is built by hand on an elevated platform so the test does not
## depend on where the generator put a hut: the platform is the resident's work
## and the empty air above it gives the attack ray a clear line of sight.
func _residents_section() -> void:
	var player: Node = _game.player
	var inventory: Inventory = _game.inventory
	player.flying = true
	player.teleport_to(Vector3(8.5, float(_test_pad_y + 5), 8.5))
	player.look_pitch(0.0)
	for i in range(2):
		await process_frame

	# Settlements are derived from the world: a wide scan must find some.
	var somewhere: Array = SettlementModel.nearby(_game.world, Vector3i(0, 70, 0), 4000, 4)
	_check(somewhere.size() > 0, "settlements are derived from placed structures (%d found)" % somewhere.size())
	if somewhere.size() > 0:
		var settlement: Dictionary = somewhere[0]
		_check(not str(settlement["name"]).is_empty(), "a settlement has a name (%s)" % settlement["name"])
		var residents := NpcModel.residents_for(_game.world.world_seed, settlement)
		_check(residents.size() > 0, "a settlement has residents")

	# A controlled settlement on an elevated platform so the resident has work and
	# the attack ray has clear air above it.
	var anchor := Vector3i(12, _test_pad_y + 1, 12)
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			for dy in range(-4, 0):
				_game.world.set_block(anchor + Vector3i(dx, dy, dz), BlockDB.STONE)
	var plot := {"id": "settlement-test", "name": "Testhold", "kind": "hut", "anchor": anchor,
		"width": 5, "depth": 4}
	var state := NpcModel.spawn_state(_game.world.world_seed, plot, 0)
	state["role"] = NpcModel.Role.MINER
	state["position"] = Vector3(12.5, float(_test_pad_y + 1), 12.5)
	_game.npc_states[str(state["id"])] = state
	_game.settlement_stores["settlement-test"] = {}
	_game._settlement_names["settlement-test"] = "Testhold"
	_game._update_npcs(0.1)
	_check(_game.npc_nodes.size() == 1, "the resident gets a scene node")
	var node: Node = _game.npc_nodes.get(str(state["id"]), null)
	_check(node != null and node.is_in_group("npc"), "the resident node is in the npc group")
	_check(node != null and node.is_alive(), "the resident node is alive")

	# The real work loop: the resident mines the platform and carries it home.
	var steps := 0
	while int(state["gathered"]) == 0 and steps < 600:
		_game._update_npcs(0.2)
		steps += 1
	_check(int(state["gathered"]) > 0, "the resident gathered a block through the game loop (%d steps)" % steps)
	_check(NpcModel.carried_total(state) > 0 or int(state["delivered"]) > 0, "the resident carries what it mined")
	_check(NpcModel.carried_total(state) <= NpcModel.CARRY_CAP, "the resident never carries more than its cap")

	# The player targets and kills the resident with its own attack path.  Aim
	# directly above the resident's *current* node: the work loop may have walked
	# it away from its spawn cell while gathering, and clear the air column so the
	# attack ray is not blocked by terrain above the resident.
	var resident_cell := Vector3i(floori(node.global_position.x), floori(node.global_position.y),
		floori(node.global_position.z))
	for dy in range(1, 5):
		_game.world.set_block(resident_cell + Vector3i(0, dy, 0), BlockDB.AIR)
	player.teleport_to(node.global_position + Vector3(0.0, 2.5, 0.0))
	player.look_pitch(-89.0)
	for i in range(3):
		await physics_frame
	var targeted: Node = player._creature_in_front()
	_check(targeted != null and targeted.is_in_group("npc")
		and str(targeted.state.get("id", "")) == str(state["id"]),
		"the player's attack ray targets the resident")
	_check(_game._npc_target_text().contains(str(state["name"])),
		"the readout describes the resident under the crosshair (%s)" % _game._npc_target_text())
	_check(_game._npc_target_text().contains(NpcModel.role_name(int(state["role"]))),
		"the readout names the resident's role")
	state["carried"] = {BlockDB.COBBLESTONE: 2}
	var cobble_before := inventory.count_of(BlockDB.COBBLESTONE)
	var hits := 0
	while is_instance_valid(node) and hits < 30:
		player.break_target()
		await physics_frame
		hits += 1
	_check(not is_instance_valid(node), "the player killed the resident in %d hits" % hits)
	_check(inventory.count_of(BlockDB.COBBLESTONE) >= cobble_before + 2,
		"the dead resident dropped what it carried")
	_check(not bool(state["alive"]), "the dead resident stays dead")

	# The store and the residents survive a save round-trip.
	_game.settlement_stores["settlement-test"] = {BlockDB.OAK_LOG: 5, ItemDB.COAL: 2}
	var payload: Dictionary = _game._npcs_to_dictionary()
	_check((payload["settlements"] as Array).size() >= 1, "the save payload carries the settlement")
	_check((payload["npcs"] as Array).size() >= 1, "the save payload carries the resident")
	_game.npc_states.clear()
	_game.settlement_stores.clear()
	var restored: int = _game._apply_npcs(payload)
	_check(restored >= 1, "the residents were restored from the payload")
	_check(_game.npc_states.has(str(state["id"])), "the resident id survived")
	var restored_store: Dictionary = _game.settlement_stores.get("settlement-test", {})
	_check(int(restored_store.get(BlockDB.OAK_LOG, 0)) == 5, "the settlement store survived")
	_check(str(_game._settlement_names.get("settlement-test", "")) == "Testhold",
		"the settlement name survived")
	_raid_section()
	_game.npc_states.clear()
	_game.settlement_stores.clear()
	_game.npc_nodes.clear()
	player.teleport_to(Vector3(8.5, float(_test_pad_y + 5), 8.5))
	player.look_pitch(-20.0)
	for i in range(2):
		await process_frame


## A night raid: raiders spawn around the settlement, the residents fight back and
## the raid ends.  The raiders are real grunt nodes and the fight resolves through
## the same attack path the player uses.
func _raid_section() -> void:
	# A live resident to defend the place.
	var defender := NpcModel.spawn_state(_game.world.world_seed, {
		"id": "settlement-test", "name": "Testhold", "kind": "hut", "anchor": Vector3i(12, _test_pad_y + 1, 12),
		"width": 5, "depth": 4,
	}, 0)
	defender["role"] = NpcModel.Role.MINER
	_game.npc_states[str(defender["id"])] = defender
	_game.settlement_stores["settlement-test"] = {}
	# The raid targets the settlements the game has already derived; a stand-in
	# entry keeps the test independent of where the world put a hut.
	_game.settlements = [{"id": "settlement-test", "name": "Testhold", "kind": "hut",
		"anchor": Vector3i(12, _test_pad_y + 1, 12), "width": 5, "depth": 4, "distance": 4.0}]
	_game._update_npcs(0.1)
	# Force the raid so the test does not depend on the clock.
	_game._options["raid_now"] = true
	_game._raid_settlement = ""
	_game._raided_day = -1
	_game._update_raid(0.1)
	_check(not _game.raid_nodes.is_empty(), "a raid spawns raiders (%d)" % _game.raid_nodes.size())
	_check(_game.raid_nodes.size() <= RaidModel.GROUP_MAX, "the raider group is within its bounds")
	var a_raider: Node = null
	for id: Variant in _game.raid_nodes.keys():
		a_raider = _game.raid_nodes[id]
		break
	_check(a_raider != null and is_instance_valid(a_raider) and a_raider.is_alive(), "the raider exists")
	_check(a_raider != null and a_raider.is_in_group("hostile_creature"), "a raider is a real hostile node")
	_check(a_raider != null and a_raider.target != null and a_raider.target.is_in_group("npc"),
		"a raider targets a resident, not the player")
	var raider_id := str(a_raider.state["id"]) if a_raider != null else ""

	# The resident defends: it walks at a raider and strikes it.
	var struck := false
	var steps := 0
	while not struck and steps < 400:
		var threats: Array = _game._raid_threats()
		if not threats.is_empty():
			var result: Dictionary = NpcModel.step(defender, _game.world,
				_game.settlement_stores["settlement-test"], 0.25, threats)
			if int(result["attack"]) >= 0:
				struck = true
				_game._apply_npc_events(defender, result)
		steps += 1
	_check(struck, "the resident strikes at a raider (%d steps)" % steps)
	_check(int(defender["task"]) == NpcModel.Task.DEFEND or int(defender["task"]) == NpcModel.Task.SEEK,
		"the resident is defending the settlement")
	_check(_game.raid_nodes.has(raider_id), "the raider the resident fought is still tracked")

	# A raid resolves: with the raiders gone, the raid ends and is not restarted.
	for id: Variant in _game.raid_nodes.keys():
		var node: Variant = _game.raid_nodes[id]
		if node != null and is_instance_valid(node):
			(node as Node).queue_free()
	_game.raid_nodes.clear()
	_game._update_raid(0.5)
	_check(_game.raid_nodes.is_empty(), "the raid is over once the raiders are gone")
	_check(int(_game._raided_day) >= 0, "the day is marked as raided")
	_game._options.erase("raid_now")
	_game.npc_states.erase(str(defender["id"]))


# =========================================================================
# Interactive world-object stations (M19)
# =========================================================================

## Puts the player three metres above a cell and looking straight down, so the
## real voxel ray targets it.  The cells above must be air.
func _aim_at(cell: Vector3i) -> void:
	var player: Node = _game.player
	player.flying = true
	player.teleport_to(Vector3(cell) + Vector3(0.5, 3.0, 0.5))
	player.look_yaw(0.0)
	player.look_pitch(-89.0)
	for i in range(2):
		await process_frame


## Looks at a cell from an arbitrary eye position, so a station can be tested
## from a diagonal rather than only from straight above.
func _aim_from(eye: Vector3, cell: Vector3i) -> void:
	var player: Node = _game.player
	player.flying = true
	player.teleport_to(eye)
	var origin: Vector3 = eye + Vector3.UP * VoxelPlayer.EYE_HEIGHT
	var delta: Vector3 = (Vector3(cell) + Vector3.ONE * 0.5) - origin
	player.look_yaw(rad_to_deg(atan2(-delta.x, -delta.z)))
	player.look_pitch(rad_to_deg(atan2(delta.y, Vector2(delta.x, delta.z).length())))
	for i in range(2):
		await process_frame


func _press_interact() -> void:
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	_game._unhandled_input(event)


## M21: plant/grow/harvest through the real player controller, cook meat in a
## real furnace station, and persist a real chest through save/reload.
func _m21_gameplay_section() -> void:
	var player: Node = _game.player
	var inventory: Inventory = _game.inventory
	var world: VoxelWorld = _game.world
	player.flying = true
	if _game.inventory_panel.is_open():
		_game._close_inventory()

	# --- farming -----------------------------------------------------------
	var soil := Vector3i(32, 75, 20)
	world.ensure_chunk(VoxelWorld.world_to_chunk(soil))
	for dy in range(1, 12):
		world.set_block(soil + Vector3i(0, dy, 0), BlockDB.AIR)
	world.set_block(soil, BlockDB.DIRT)
	await _aim_at(soil)
	var soil_hit: Dictionary = player.target()
	_check(soil_hit.get("hit", false) and Vector3i(soil_hit["block"]) == soil,
		"the crosshair targets the soil cell for planting")
	# Put seeds in the selected slot and plant with the real build action.
	inventory.clear_slot(0)
	inventory.put_stack(0, {"item": ItemDB.WHEAT_SEEDS, "count": 4})
	inventory.select(0)
	var seeds_before := inventory.count_of(ItemDB.WHEAT_SEEDS)
	_check(player.place_selected(), "right-click with seeds is handled by the farming action")
	_check(world.get_block(soil) == BlockDB.FARMLAND, "planting tills the targeted soil")
	_check(world.get_block(soil + Vector3i.UP) == BlockDB.WHEAT_0, "planting creates a real crop block")
	_check(inventory.count_of(ItemDB.WHEAT_SEEDS) == seeds_before - 1, "planting consumes exactly one seed")
	_check(_game.farming.count() == 1, "the planted crop is tracked for growth")

	# Save/reload must preserve both the crop block and its growth timer.
	_game._save_now()
	await process_frame
	_game._reload_now()
	await process_frame
	_check(world.get_block(soil + Vector3i.UP) == BlockDB.WHEAT_0,
		"the planted crop block survives save/reload")
	_check(_game.farming.count() == 1, "the crop growth timer survives save/reload")

	# Time advances the crop through the real game model.
	_game.farming.step(Farming.STAGE_SECONDS * 3.1, world, player.global_position)
	_check(world.get_block(soil + Vector3i.UP) == BlockDB.WHEAT_3, "the crop ripens over time")

	# Harvest by breaking the targeted crop with the real player path.
	await _aim_at(soil + Vector3i.UP)
	var wheat_before := inventory.count_of(ItemDB.WHEAT)
	var seed_count_before := inventory.count_of(ItemDB.WHEAT_SEEDS)
	_check(player.break_target(), "a ripe crop can be harvested through the real break path")
	await process_frame
	_check(world.get_block(soil + Vector3i.UP) == BlockDB.AIR, "the harvested crop leaves the world")
	_check(inventory.count_of(ItemDB.WHEAT) >= wheat_before + 2, "harvesting adds wheat to the inventory")
	_check(inventory.count_of(ItemDB.WHEAT_SEEDS) > seed_count_before, "harvesting returns seeds for replanting")

	# --- cooking -----------------------------------------------------------
	var furnace := StationModel.new(StationModel.FURNACE)
	furnace.inventory.insert(StationModel.FURNACE_INPUT_SLOT, {"item": ItemDB.RAW_MEAT, "count": 1})
	furnace.inventory.insert(StationModel.FURNACE_FUEL_SLOT, {"item": ItemDB.COAL, "count": 1})
	furnace.step(Smelting.cook_seconds(Smelting.recipe_for(ItemDB.RAW_MEAT)) + 0.2)
	_check(furnace.inventory.total_of(ItemDB.COOKED_MEAT) == 1,
		"a real timed furnace cooks raw meat into cooked meat")
	_check(furnace.inventory.total_of(ItemDB.RAW_MEAT) == 0, "cooking consumes the raw meat exactly once")

	# --- storage chest -----------------------------------------------------
	var chest_cell := Vector3i(34, 75, 20)
	world.ensure_chunk(VoxelWorld.world_to_chunk(chest_cell))
	for dy in range(1, 12):
		world.set_block(chest_cell + Vector3i(0, dy, 0), BlockDB.AIR)
	world.set_block(chest_cell, BlockDB.CHEST)
	await _aim_at(chest_cell)
	_check(_game.targeted_station_position() == chest_cell, "the crosshair identifies the placed chest")
	_press_interact()
	await process_frame
	var panel = _game.station_panel
	_check(panel.is_open(), "E opens the storage chest")
	_check(panel.station_slot_count() == StationModel.CHEST_SLOTS, "the chest interface shows 27 slots")
	var chest = _game.stations.peek(chest_cell)
	_check(chest != null and chest.is_storage(), "the opened station is a storage chest")
	# Move a real player stack into the chest and save/reload it.
	inventory.clear_slot(1)
	inventory.put_stack(1, {"item": BlockDB.COBBLESTONE, "count": 11})
	var chest_player_slot := 1
	var chest_cobble := inventory.count_of(BlockDB.COBBLESTONE)
	_check(panel.quick_move("player", chest_player_slot), "shift-click moves a stack into the chest")
	_check(chest.inventory.total_of(BlockDB.COBBLESTONE) == 11, "the chest received the exact stack")
	_check(inventory.count_of(BlockDB.COBBLESTONE) == chest_cobble - 11,
		"moving the stack conserved the player's cobblestone")
	_game._save_now()
	await process_frame
	_game._reload_now()
	await process_frame
	var restored_chest = _game.stations.peek(chest_cell)
	_check(restored_chest != null and restored_chest.is_storage(), "the chest survives save/reload")
	if restored_chest != null:
		_check(restored_chest.inventory.total_of(BlockDB.COBBLESTONE) == 11,
			"the chest contents survive save/reload exactly once")
	_game._close_station()
	await process_frame
	# Break the chest and recover its contents through the real player path.
	await _aim_at(chest_cell)
	var recovered_before := inventory.count_of(BlockDB.COBBLESTONE)
	_check(player.break_target(), "the chest can be broken through the player path")
	await process_frame
	_check(inventory.count_of(BlockDB.COBBLESTONE) == recovered_before + 11,
		"breaking the chest recovers its contents exactly once")
	_game.saves.delete_save()


func _stations_section() -> void:
	var player: Node = _game.player
	var inventory: Inventory = _game.inventory
	var world: VoxelWorld = _game.world
	var panel = _game.station_panel
	# The inventory section closed its panel directly; restore the play state so
	# this section starts from a clean, interactive baseline.
	if _game.inventory_panel.is_open():
		_game._close_inventory()
	else:
		player.can_interact = true
	player.flying = true

	# A clear two-station site near spawn, in cells the streamer has loaded.  The
	# column above is cleared well past the camera so the test aims at the
	# station rather than at a hillside.
	var table_cell := Vector3i(20, 76, 20)
	var furnace_cell := Vector3i(24, 76, 20)
	for cell: Vector3i in [table_cell, furnace_cell]:
		for dy in range(1, 12):
			world.set_block(cell + Vector3i(0, dy, 0), BlockDB.AIR)
		world.set_block(cell, BlockDB.AIR)
	world.set_block(table_cell, BlockDB.CRAFTING_TABLE)

	# --- targeting and opening --------------------------------------------
	# Clear a small air box around the station so a diagonal eye position is
	# valid test space, then approach it from that angle and from straight above.
	for dy in range(1, 7):
		for dx in range(-3, 4):
			for dz in range(-3, 4):
				world.set_block(table_cell + Vector3i(dx, dy, dz), BlockDB.AIR)
	await _aim_from(Vector3(table_cell) + Vector3(-2.0, 3.2, 2.0), table_cell)
	_check(_game.targeted_station_position() == table_cell,
		"the crosshair identifies the crafting table from a diagonal angle")
	_check(not _game.stations.has(table_cell), "a station has no state before it is used")
	_press_interact()
	await process_frame
	_check(panel.is_open(), "E opens the table from a diagonal angle")
	_game._close_station()
	await process_frame
	_check(not panel.is_open(), "the diagonal-angle table interface closes")

	await _aim_at(table_cell)
	_check(_game.targeted_station_position() == table_cell,
		"the crosshair identifies the placed crafting table")
	_press_interact()
	await process_frame
	_check(panel.is_open(), "E opens the targeted crafting table")
	_check(not player.can_interact, "the open station disables world interaction")
	_check(_game.stations.count() == 1, "opening a station creates exactly one state")
	_check(panel.station_slot_count() == 10,
		"the crafting table interface has a 3x3 grid and a result slot")
	var table = _game.stations.peek(table_cell)
	_check(table != null and table.kind == StationModel.TABLE, "the opened station is a crafting table")

	# --- moving items between the two inventories -------------------------
	inventory.clear_slot(0)
	inventory.clear_slot(1)
	inventory.clear_slot(2)
	# The starter kit now begins with a full planks stack.  Remove every planks
	# stack first so this stack-movement check has exactly one fresh source stack
	# instead of merging into an unrelated partially used starter stack.
	for index in Inventory.SIZE:
		if inventory.item_at(index) == BlockDB.PLANKS:
			inventory.clear_slot(index)
	inventory.add(BlockDB.PLANKS, 12)
	var planks_slot: int = inventory.slots.find(BlockDB.PLANKS)
	_check(planks_slot >= 0, "the player holds planks for the grid")
	var planks_before := inventory.count_of(BlockDB.PLANKS)
	_check(panel.pick_up("player", planks_slot), "a stack can be picked up from the player inventory")
	_check(not panel.carried().is_empty(), "the picked-up stack is carried")
	panel.click_slot("station", 0)
	_check(table.inventory.total_of(BlockDB.PLANKS) == 1,
		"a left-click places one item in a crafting-grid cell, not the whole stack")
	_check(int(panel.carried().get("count", 0)) == planks_before - 1,
		"the rest of the stack stays on the cursor")
	_check(panel.status_text().contains("No matching recipe"),
		"an incomplete grid reports that nothing matches")
	var expected_grid_planks := 1
	for grid_slot in [1, 3, 4]:
		panel.click_slot("station", grid_slot)
		expected_grid_planks += 1
		_check(table.inventory.total_of(BlockDB.PLANKS) == expected_grid_planks,
			"another plank moves into grid cell %d" % grid_slot)
	var empty_slot: int = inventory.slots.find(BlockDB.AIR)
	_check(empty_slot >= 0, "the player has a free slot for the remainder")
	_check(panel.put_down("player", empty_slot), "the carried remainder returns to the player")
	_check(inventory.count_of(BlockDB.PLANKS) == planks_before - 4,
		"exactly four planks left the player inventory")
	_check(table.inventory.total_of(BlockDB.PLANKS) == 4, "exactly four planks are in the grid")
	_check(table.inventory.total_items() == 4, "the station and the player hold every item exactly once")

	# --- crafting from the grid -------------------------------------------
	var preview: Dictionary = table.result_preview()
	_check(int(preview.get("output", -1)) == BlockDB.CRAFTING_TABLE,
		"the 3x3 grid previews a crafting table")
	_check(panel.status_text().contains("Ready"), "the interface confirms the recipe is ready")
	var tables_before := inventory.count_of(BlockDB.CRAFTING_TABLE)
	_check(panel.take_output(), "the result can be taken from the table")
	var carried: Dictionary = panel.carried()
	_check(int(carried.get("item", -1)) == BlockDB.CRAFTING_TABLE,
		"taking the result carries the crafted table")
	var table_slot: int = inventory.slots.find(BlockDB.AIR)
	_check(table_slot >= 0, "the player has a free slot for the crafted table")
	_check(panel.put_down("player", table_slot), "the crafted table moves into the player inventory")
	_check(inventory.count_of(BlockDB.CRAFTING_TABLE) == tables_before + 1,
		"the crafted table reached the player")
	_check(table.inventory.total_of(BlockDB.PLANKS) == 0,
		"the craft consumed exactly the four grid planks")
	_check(table.inventory.is_empty(StationModel.TABLE_OUTPUT_SLOT),
		"the result slot is empty after the crafted item was taken")

	# A shaped 3x3 recipe through the station model: the catalogue's stone axe
	# pattern (three cobblestone, two sticks) must match and produce its tool.
	table.inventory.clear_all()
	for grid_index in [0, 1, 3]:
		table.inventory.insert(grid_index, {"item": BlockDB.COBBLESTONE, "count": 1})
	for grid_index in [4, 7]:
		table.inventory.insert(grid_index, {"item": ItemDB.STICK, "count": 1})
	var shaped_preview: Dictionary = table.result_preview()
	_check(int(shaped_preview.get("output", -1)) == ItemDB.STONE_AXE,
		"the 3x3 grid matches the shaped stone-axe recipe")
	var axe_before := inventory.count_of(ItemDB.STONE_AXE)
	_check(panel.take_output(), "the shaped result can be taken")
	var shaped_carried: Dictionary = panel.carried()
	_check(int(shaped_carried.get("item", -1)) == ItemDB.STONE_AXE,
		"the shaped craft carries a stone axe")
	var axe_slot_player: int = inventory.slots.find(BlockDB.AIR)
	_check(panel.put_down("player", axe_slot_player), "the shaped tool reaches the player inventory")
	_check(inventory.count_of(ItemDB.STONE_AXE) == axe_before + 1,
		"the shaped craft produced exactly one stone axe")
	var crafted_axe_slot: int = inventory.slots.find(ItemDB.STONE_AXE)
	_check(crafted_axe_slot >= 0 and inventory.durability_of(crafted_axe_slot) ==
		ItemDB.max_durability(ItemDB.STONE_AXE), "the shaped tool arrives at full durability")
	_check(table.inventory.total_items() == 0, "the shaped craft consumed every grid ingredient")
	table.inventory.clear_all()

	# Shift-click and drag & drop move whole stacks between the two inventories.
	inventory.clear_slot(2)
	inventory.add(ItemDB.STICK, 6)
	var stick_slot: int = inventory.slots.find(ItemDB.STICK)
	_check(stick_slot >= 0, "the player holds sticks for the quick-move test")
	var quick_sticks_before := inventory.count_of(ItemDB.STICK)
	var stick_stack := inventory.counts[stick_slot]
	_check(panel.quick_move("player", stick_slot), "shift-click moves a whole stack into the station")
	_check(inventory.count_of(ItemDB.STICK) == quick_sticks_before - stick_stack,
		"shift-click removed exactly that stack from the player")
	_check(table.inventory.total_of(ItemDB.STICK) == stick_stack,
		"the station received the whole stack")
	var station_stick_slots: Array[int] = []
	for index in table.inventory.size():
		if table.inventory.item_at(index) == ItemDB.STICK:
			station_stick_slots.append(index)
	_check(not station_stick_slots.is_empty(), "the moved sticks are in station slots")
	for station_stick_slot: int in station_stick_slots:
		_check(panel.move_between("station", station_stick_slot, "player", stick_slot),
			"drag & drop moves each station stick stack back to the player")
	_check(inventory.count_of(ItemDB.STICK) == quick_sticks_before,
		"the drag & drop move conserved every stick")
	_check(table.inventory.total_of(ItemDB.STICK) == 0,
		"the station no longer holds the sticks")

	# Regression: a station -> player shift-click must not also restore the stack
	# into the station (the old handler used the original count as the default
	# leftover when adding to the player, duplicating the whole stack).
	table.inventory.clear_all()
	table.inventory.insert(5, {"item": ItemDB.STICK, "count": 5})
	var sticks_before_shift := inventory.count_of(ItemDB.STICK)
	_check(panel.quick_move("station", 5), "shift-click moves a station stack to the player")
	_check(inventory.count_of(ItemDB.STICK) == sticks_before_shift + 5,
		"the player received exactly five sticks from the station")
	_check(table.inventory.total_of(ItemDB.STICK) == 0,
		"the station stack was not duplicated back into the station")

	# Regression: right-click one item onto an incompatible occupied slot must
	# refuse without swapping or losing the target stack.
	inventory.clear_slot(27)
	inventory.put_stack(27, {"item": BlockDB.SAND, "count": 10, "durability": 0})
	table.inventory.insert(6, {"item": ItemDB.IRON_LUMP, "count": 3})
	panel.pick_up("station", 6)
	_check(not panel.put_one("player", 27),
		"right-click one onto an incompatible player stack is refused")
	_check(inventory.item_at(27) == BlockDB.SAND and inventory.count_at(27) == 10,
		"the incompatible target stack is untouched")
	_check(int(panel.carried().get("count", 0)) == 3,
		"the cursor still holds all three iron lumps")
	_check(panel.put_down("station", 6), "the cursor iron returns to the station")
	_check(table.inventory.total_of(ItemDB.IRON_LUMP) == 3,
		"the station still owns exactly three iron lumps")
	table.inventory.clear_all()

	# --- the interface blocks accidental world actions ---------------------
	_game._close_station()
	await process_frame
	_check(not panel.is_open(), "the station interface closes")
	_check(player.can_interact, "closing the station restores world interaction")
	await _aim_at(table_cell)
	_press_interact()
	await process_frame
	_check(panel.is_open(), "the station can be opened again")
	Input.action_press("break_block")
	for i in range(8):
		await process_frame
	Input.action_release("break_block")
	_check(_game.world.get_block(table_cell) == BlockDB.CRAFTING_TABLE,
		"holding the mine action does not break the block while the interface is open")
	_check(_game.world.get_block(table_cell + Vector3i.UP) == BlockDB.AIR,
		"no accidental placement happened while the interface was open")

	# --- the furnace: a separate station with its own inventory -----------
	world.set_block(furnace_cell, BlockDB.FURNACE)
	_game._close_station()
	await _aim_at(furnace_cell)
	_check(_game.targeted_station_position() == furnace_cell, "the crosshair identifies the placed furnace")
	_press_interact()
	await process_frame
	_check(panel.is_open(), "E opens the targeted furnace")
	_check(_game.stations.count() == 2, "two nearby stations each have their own state")
	_check(panel.station_slot_count() == 3,
		"the furnace interface has input, fuel and output slots")
	var furnace = _game.stations.peek(furnace_cell)
	_check(furnace != null and furnace.kind == StationModel.FURNACE, "the opened station is a furnace")
	_check(table.inventory.total_items() == 0, "the furnace did not receive the table's items")

	inventory.clear_slot(3)
	inventory.clear_slot(4)
	var sand_slot: int = inventory.slots.find(BlockDB.AIR)
	_check(sand_slot >= 0, "the player has an empty slot for the furnace input")
	inventory.put_stack(sand_slot, {"item": BlockDB.SAND, "count": 3, "durability": 0})
	var coal_slot: int = inventory.slots.find(BlockDB.AIR)
	_check(coal_slot >= 0, "the player has an empty slot for the furnace fuel")
	inventory.put_stack(coal_slot, {"item": ItemDB.COAL, "count": 1, "durability": 0})
	panel.pick_up("player", sand_slot)
	_check(panel.put_down("station", StationModel.FURNACE_INPUT_SLOT),
		"the input slot accepts sand")
	panel.pick_up("player", coal_slot)
	_check(panel.put_down("station", StationModel.FURNACE_FUEL_SLOT),
		"the fuel slot accepts coal")
	_check(furnace.inventory.total_of(BlockDB.SAND) == 3, "the furnace holds the input")
	_check(furnace.inventory.total_of(ItemDB.COAL) == 1, "the furnace holds the fuel")
	_check(panel.status_text().contains("Smelting"), "the furnace explains what it will smelt")

	var glass_before := inventory.count_of(BlockDB.GLASS)
	var changes: int = _game.stations.tick(6.5, player.global_position)
	_check(changes > 0, "the furnace advances with time through the registry")
	panel.refresh()
	_check(furnace.inventory.count_at(StationModel.FURNACE_OUTPUT_SLOT) >= 1,
		"the furnace produced glass in its output slot")
	_check(furnace.inventory.total_of(BlockDB.SAND) == 2, "one sand was consumed")
	_check(furnace.inventory.total_of(ItemDB.COAL) == 0, "one coal was burned")
	_check(panel.status_text().contains("Furnace is"), "the interface reports the furnace state")
	_check(panel.take_output(), "the furnace result can be taken")
	var glass_slot: int = inventory.slots.find(BlockDB.AIR)
	_check(panel.put_down("player", glass_slot), "the furnace result moves to the player")
	_check(inventory.count_of(BlockDB.GLASS) == glass_before + 1,
		"the smelted glass reached the player")

	# --- persistence across save/load --------------------------------------
	_game._close_station()
	await process_frame
	var stored = _game.stations.station_at(table_cell)
	stored.inventory.clear_all()
	stored.inventory.insert(5, {"item": ItemDB.STICK, "count": 5})
	_game._save_now()
	_check(FileAccess.file_exists(_game.saves.save_path()), "the station save is written to disk")
	_game.stations.from_dictionary([])
	_check(_game.stations.count() == 0, "station state can be cleared to prove it comes from disk")
	_game._reload_now()
	await process_frame
	var restored_table = _game.stations.peek(table_cell)
	_check(restored_table != null, "the table state is restored on load")
	if restored_table != null:
		_check(restored_table.inventory.total_of(ItemDB.STICK) == 5,
			"the table contents survive save/load")
	var restored_furnace = _game.stations.peek(furnace_cell)
	_check(restored_furnace != null, "the furnace state is restored on load")
	if restored_furnace != null:
		_check(restored_furnace.inventory.total_of(BlockDB.SAND) == 2,
			"the furnace input survives save/load")
		_check(restored_furnace.burn_remaining > 0.0,
			"the furnace burn time survives save/load")

	# --- chunk unload and reload ------------------------------------------
	var coord := VoxelWorld.world_to_chunk(table_cell)
	_game.world.unload_chunk(coord)
	_check(not _game.world.has_chunk(coord), "the station's chunk unloads")
	_game.world.ensure_chunk(coord)
	_check(_game.world.get_block(table_cell) == BlockDB.CRAFTING_TABLE,
		"the station block returns when the chunk reloads")
	var after_chunk = _game.stations.peek(table_cell)
	_check(after_chunk != null and after_chunk.inventory.total_of(ItemDB.STICK) == 5,
		"the station contents survive chunk unload/reload")

	# --- destruction returns the contents ---------------------------------
	await _aim_at(table_cell)
	_check(_game.targeted_station_position() == table_cell, "the restored station is targetable")
	var sticks_before := inventory.count_of(ItemDB.STICK)
	var table_blocks_before := inventory.count_of(BlockDB.CRAFTING_TABLE)
	var broke: bool = player.break_target()
	await process_frame
	_check(broke, "the targeted station can be broken")
	_check(_game.world.get_block(table_cell) == BlockDB.AIR, "the station block is gone")
	_check(not _game.stations.has(table_cell), "the destroyed station's state is removed")
	_check(inventory.count_of(ItemDB.STICK) == sticks_before + 5,
		"the station contents were recovered when it was destroyed")
	_check(inventory.count_of(BlockDB.CRAFTING_TABLE) == table_blocks_before + 1,
		"the station block itself dropped")

	# --- invalid interaction and interaction range -------------------------
	var range_cell := Vector3i(28, 76, 20)
	for dy in range(1, 12):
		world.set_block(range_cell + Vector3i(0, dy, 0), BlockDB.AIR)
	world.set_block(range_cell, BlockDB.AIR)
	world.set_block(range_cell, BlockDB.CRAFTING_TABLE)
	await _aim_at(range_cell)
	_check(_game.targeted_station_position() == range_cell,
		"a nearby station is targetable inside the interaction range")
	player.look_pitch(45.0)
	await process_frame
	_game._try_interact()
	await process_frame
	_check(not panel.is_open(), "interacting with the sky opens nothing")
	player.teleport_to(Vector3(range_cell) + Vector3(0.5, 10.0, 0.5))
	player.flying = true
	player.look_pitch(-89.0)
	for i in range(2):
		await process_frame
	var beyond: Dictionary = player.target()
	_check(not beyond.get("hit", false) or Vector3i(beyond["block"]) != range_cell,
		"a station beyond the interaction range is not targetable")
	_game._try_interact()
	await process_frame
	_check(not panel.is_open(), "a station beyond the interaction range cannot be opened")
	world.set_block(range_cell, BlockDB.AIR)

	# Leave no save behind for later captures or sessions.
	_game.saves.delete_save()
	player.teleport_to(Vector3(8.5, float(_test_pad_y + 5), 8.5))
	player.look_pitch(-20.0)
	for i in range(2):
		await process_frame


## A save or a reload must never leave the temporary cursor stack as a second
## copy, and must never drop it either.  This is the real-scene regression for
## "duplicate items through persistence": before the fix, a reload while the
## inventory was open restored the stack into its slot while the cursor kept its
## copy, doubling the item.
func _persistence_cursor_section() -> void:
	var inventory: Inventory = _game.inventory
	var panel = _game.inventory_panel
	panel.close()
	await process_frame

	# A stack in a storage slot is the reference the duplicates were measured
	# against.
	inventory.clear_slot(20)
	inventory.put_stack(20, {"item": BlockDB.COBBLESTONE, "count": 9})
	var cobble_total := inventory.count_of(BlockDB.COBBLESTONE)
	_game._save_now()
	await process_frame
	_check(FileAccess.file_exists(_game.saves.save_path()), "the cursor regression save is written")

	# Saving while a stack is held must put it in the model first.
	_game._open_inventory()
	await process_frame
	_check(panel.pick_up(20), "a storage stack is picked up before the save")
	_check(not panel.carried().is_empty(), "the stack sits on the cursor before the save")
	_game._save_now()
	await process_frame
	_check(panel.carried().is_empty(), "saving returns the cursor stack to the model")
	_check(inventory.count_of(BlockDB.COBBLESTONE) == cobble_total,
		"saving a held stack conserves the cobblestone total")

	# A reload while the interface is open must return the cursor first.
	inventory.clear_slot(21)
	inventory.put_stack(21, {"item": ItemDB.IRON_LUMP, "count": 4})
	var iron_total := inventory.count_of(ItemDB.IRON_LUMP)
	_game._save_now()
	await process_frame
	var iron_origin: int = inventory.slots.find(ItemDB.IRON_LUMP)
	_check(panel.pick_up(iron_origin), "the iron stack is picked up before the reload")
	var cobble_before := inventory.count_of(BlockDB.COBBLESTONE)
	_game._reload_now()
	await process_frame
	_check(not panel.is_open(), "the inventory interface closes before a reload")
	_check(panel.carried().is_empty(), "the cursor stack is returned before the reload")
	_check(inventory.count_of(ItemDB.IRON_LUMP) == iron_total,
		"reloading with an open inventory does not duplicate the iron")
	_check(inventory.count_of(BlockDB.COBBLESTONE) == cobble_before,
		"reloading with an open inventory does not duplicate the cobblestone")

	_game.saves.delete_save()
	await process_frame


## M28 end-to-end proof: build the player-authored village/castle in the live
## world, save through the real SaveManager, reload, and verify the settlement
## and the player's position survive.  This is the scripted equivalent of
## "build, save, quit, reopen, continue".
func _final_journey_section() -> void:
	var world: VoxelWorld = _game.world
	var player: VoxelPlayer = _game.player
	var report := FinalDemo.build(world)
	_check(int(report["castle"]) > 400, "the final journey builds a castle")
	_check(int(report["cottage"]) > 150 and int(report["longhouse"]) > 200,
		"the final journey builds a home and a village hall")
	var base: Vector3i = report["base_y"]
	var castle := base + Vector3i(FinalDemo.CASTLE_OFFSET.x, 0, FinalDemo.CASTLE_OFFSET.y)
	var cottage := base + Vector3i(FinalDemo.COTTAGE_OFFSET.x, 0, FinalDemo.COTTAGE_OFFSET.y)
	# Stand in the village so the built chunks stay loaded across the reload.
	player.teleport_to(Vector3(float(base.x) - 2.0, float(base.y) + 1.2, float(base.z) + 21.0))
	player.flying = false
	_game.streamer.focus_at(player.global_position)
	await _stream_until_settled()
	_check(_game.world.get_block(castle + Vector3i(0, 1, 8)) == BlockDB.DOOR,
		"the castle gate exists before saving")
	_check(_game.world.get_block(cottage + Vector3i(0, 1, 3)) == BlockDB.DOOR,
		"the cottage door exists before saving")
	_game._save_now()
	_check(FileAccess.file_exists(_game.saves.save_path()), "the final journey save is written")
	_game._reload_now()
	await _stream_until_settled()
	_check(_game.world.get_block(castle + Vector3i(0, 1, 8)) == BlockDB.DOOR,
		"the castle gate survives save and reload")
	_check(_game.world.get_block(cottage + Vector3i(0, 1, 3)) == BlockDB.DOOR,
		"the cottage door survives save and reload")
	_check(_game.world.get_block(base + Vector3i(0, 0, 12)) == BlockDB.PATH,
		"the village street survives save and reload")
	_check(player.global_position.distance_to(Vector3(float(base.x) - 2.0,
		float(base.y) + 1.2, float(base.z) + 21.0)) < 1.0,
		"the player position survives save and reload")
	_game.saves.delete_save()
	await process_frame

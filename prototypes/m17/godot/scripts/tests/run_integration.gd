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
const CreatureScript = preload("res://scripts/game/passive_creature.gd")
const CreatureModel = preload("res://scripts/core/passive_creatures.gd")
const HostileScript = preload("res://scripts/game/hostile_creature.gd")
const HostileModel = preload("res://scripts/core/hostile_creatures.gd")


func _initialize() -> void:
	call_deferred("_main")


func _check(condition: bool, description: String) -> void:
	if condition:
		_passes += 1
		print("M17_INT_ASSERT_PASS %s" % description)
	else:
		_failures.append(description)
		print("M17_INT_ASSERT_FAIL %s" % description)


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
func _stream_until_settled(max_frames: int = 900) -> int:
	var streamer: ChunkStreamer = _game.streamer
	var world: VoxelWorld = _game.world
	var guard := 0
	while guard < max_frames:
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
	# Exercise the creature damage/death/drop path through the real scene node and
	# game inventory integration (three separate player attacks, one drop).
	var creature_state := {"id": 9001, "species": "boar", "position": landed + Vector3(0.0, 0.0, -0.8),
		"health": 3, "alive": true, "wander": Vector3.ZERO, "key": "integration-boar"}
	var test_creature = CreatureScript.new()
	test_creature.configure(creature_state, _game.world)
	_game.creature_root.add_child(test_creature)
	test_creature.killed.connect(_game._on_creature_killed)
	var drops_before: int = _game.inventory.count_of(CreatureModel.DROP_ID)
	player.flying = true
	player.teleport_to(landed)
	player.look_yaw(0.0)
	player.look_pitch(-70.0)
	for i in range(2):
		await physics_frame
	_check(player._creature_in_front() == test_creature, "LMB targeting prioritizes the closer passive creature")
	_check(player.break_target() and int(test_creature.state.health) == 2,
		"first player interaction damages a living passive creature")
	player.break_target()
	_check(player.break_target() and not bool(test_creature.state.alive), "lethal player interaction kills the creature")
	await process_frame
	_check(_game.inventory.count_of(CreatureModel.DROP_ID) == drops_before + 1,
		"one creature death adds exactly one useful item to inventory")

	# Hostile creatures: contact damage, player combat and loot through the real
	# scene node and game inventory integration.
	var hostile_state := {"id": 9100, "species": "grunt", "position": landed + Vector3(0.0, 0.0, -0.9),
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
	var hostile_loot_before: int = _game.inventory.count_of(HostileModel.DROP_ID)
	for i in range(HostileModel.HIT_POINTS):
		player.break_target()
	await process_frame
	_check(not is_instance_valid(test_hostile), "player hits kill the hostile grunt")
	_check(_game.inventory.count_of(HostileModel.DROP_ID) == hostile_loot_before + HostileModel.DROP_COUNT,
		"a hostile death adds its loot item")

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

	if _failures.is_empty():
		print("M17_INTEGRATION_PASS %d assertions" % _passes)
		quit(0)
	else:
		for failure: String in _failures:
			print("M17_INTEGRATION_FAILURE %s" % failure)
		print("M17_INTEGRATION_FAIL %d failures, %d passes" % [_failures.size(), _passes])
		quit(1)

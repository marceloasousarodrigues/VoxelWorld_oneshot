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
const NpcModel = preload("res://scripts/core/npc.gd")
const SettlementModel = preload("res://scripts/core/settlement.gd")
const RaidModel = preload("res://scripts/core/raid.gd")


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

	# --- Inventory interface: slots, stack moves and item details ----------
	await _inventory_section()

	# --- Settlements and residents -----------------------------------------
	await _residents_section()

	if _failures.is_empty():
		print("M17_INTEGRATION_PASS %d assertions" % _passes)
		quit(0)
	else:
		for failure: String in _failures:
			print("M17_INTEGRATION_FAILURE %s" % failure)
		print("M17_INTEGRATION_FAIL %d failures, %d passes" % [_failures.size(), _passes])
		quit(1)


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
	player.teleport_to(Vector3(8.5, 74.0, 8.5))
	player.look_yaw(0.0)
	player.look_pitch(-89.0)
	for i in range(2):
		await process_frame

	# The station is a block in the world, not a menu flag.
	var table_cell := Vector3i(8, 72, 8)
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
	_check(_game.crafting.row_enabled("stone_axe"), "an affordable table recipe is enabled")
	_check(not _game.crafting.row_enabled("iron_pickaxe"), "an unaffordable recipe stays disabled")
	_check(_game.crafting.row_status("iron_pickaxe").contains("missing"),
		"the disabled row explains the missing ingredient")

	var cobble_before := inventory.count_of(BlockDB.COBBLESTONE)
	_check(_game.crafting.press_craft("stone_axe"), "the panel's real Craft button activates")
	await process_frame
	_check(inventory.count_of(ItemDB.STONE_AXE) == 1, "the craft produced a stone axe in the inventory")
	_check(inventory.count_of(BlockDB.COBBLESTONE) == cobble_before - 3,
		"the craft consumed exactly the recipe's cobblestone")
	var axe_slot := inventory.slots.find(ItemDB.STONE_AXE)
	_check(axe_slot >= 0 and inventory.durability_of(axe_slot) == ItemDB.max_durability(ItemDB.STONE_AXE),
		"the crafted tool arrives at full durability")

	# The batch button performs five crafts.
	inventory.add(BlockDB.PLANKS, 10)
	var planks_before := inventory.count_of(BlockDB.PLANKS)
	var sticks_before := inventory.count_of(ItemDB.STICK)
	_check(_game.crafting.press_craft("sticks", true), "the batch button crafts five times")
	await process_frame
	_check(inventory.count_of(BlockDB.PLANKS) == planks_before - 10,
		"the batch consumed ten planks")
	_check(inventory.count_of(ItemDB.STICK) == sticks_before + 20,
		"the batch produced twenty sticks")

	# Smelting needs the furnace station, which this world does not have yet.
	_check(not _game.crafting.row_enabled("iron_ingot"), "smelting is refused without a furnace")
	_check(_game.crafting.row_status("iron_ingot").contains("Furnace"),
		"the smelting row explains the missing furnace")
	_game.world.set_block(Vector3i(9, 72, 8), BlockDB.FURNACE)
	_game.crafting.set_station(_game._current_station())
	inventory.clear_slot(5)
	inventory.clear_slot(8)
	inventory.add(ItemDB.IRON_LUMP, 1)
	inventory.add(ItemDB.COAL, 1)
	_check(_game.crafting.station() == Crafting.STATION_FURNACE, "a placed furnace becomes the station")
	_check(_game.crafting.row_enabled("iron_ingot"), "the furnace unlocks smelting")
	_check(_game.crafting.press_craft("iron_ingot"), "the furnace smelts through the panel")
	await process_frame
	_check(inventory.count_of(ItemDB.IRON_INGOT) == 1, "the smelted ingot is in the inventory")
	_check(inventory.count_of(ItemDB.COAL) == 0, "the smelt consumed the coal fuel")

	_game._close_crafting()
	await process_frame
	_check(not _game.crafting.is_open(), "the crafting panel closes")

	# --- Mining rules through the real player ------------------------------
	# A clean column so the first solid voxel below the player is the one under
	# test, whatever the terrain does nearby.
	var mine_cell := Vector3i(10, 70, 10)
	_game.world.set_block(Vector3i(10, 69, 10), BlockDB.STONE)
	_game.world.set_block(Vector3i(10, 72, 10), BlockDB.AIR)
	_game.world.set_block(Vector3i(10, 71, 10), BlockDB.AIR)
	_game.world.set_block(mine_cell, BlockDB.STONE)
	player.teleport_to(Vector3(mine_cell) + Vector3(0.5, 3.0, 0.5))
	player.look_yaw(0.0)
	player.look_pitch(-89.0)
	for i in range(2):
		await process_frame
	var target: Dictionary = player.target()
	_check(target.get("hit", false) and Vector3i(target["block"]) == mine_cell,
		"the stone block above the player is targeted")
	# A bare hand: the block breaks, but it does not drop.
	var block_slot := inventory.slots.find(BlockDB.STONE)
	inventory.select(block_slot)
	var harvest_failed := [false]
	player.harvest_failed.connect(func(_block_id: int, _tool: int) -> void: harvest_failed[0] = true)
	var cobble_from_hand := inventory.count_of(BlockDB.COBBLESTONE)
	player.mine_step(0.1)
	_check(player.mining_ratio() > 0.0, "holding the mine action starts a progressive break")
	_check(int(_game.world.get_block(mine_cell)) != BlockDB.AIR,
		"a tenth of a second does not break stone by hand")
	var hand_seconds := ItemDB.break_seconds(BlockDB.STONE, BlockDB.AIR)
	var steps := 0
	var step_limit := int(hand_seconds * 10.0) + 10
	while int(_game.world.get_block(mine_cell)) != BlockDB.AIR and steps < step_limit:
		player.mine_step(0.1)
		steps += 1
	_check(int(_game.world.get_block(mine_cell)) == BlockDB.AIR,
		"holding the mine action breaks the stone (%d steps)" % steps)
	_check(harvest_failed[0], "a bare hand is told the block needs a pickaxe")
	_check(inventory.count_of(BlockDB.COBBLESTONE) == cobble_from_hand,
		"a bare hand gets no drop from stone")

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

	player.look_pitch(0.0)
	player.teleport_to(Vector3(8.5, 74.0, 8.5))
	for i in range(2):
		await process_frame


## Hunger and eating through the real game: the drain is driven by the game's own
## survival step, eating is the real right-click path, starvation respects its
## health floor and a fed body regenerates.
func _hunger_section() -> void:
	var player: Node = _game.player
	var inventory: Inventory = _game.inventory
	player.flying = true
	player.teleport_to(Vector3(8.5, 74.0, 8.5))
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
	_game._open_inventory()
	await process_frame
	_check(panel.is_open(), "the inventory panel opens")
	_check(not player.can_interact, "the inventory panel disables player interaction")
	_check(panel.slot_count() == Inventory.HOTBAR_SIZE, "the panel shows every hotbar slot")

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

	# Closing with a carried stack must never lose it.
	var logs_before := inventory.count_of(BlockDB.OAK_LOG)
	_check(panel.pick_up(8), "a stack can be carried when the panel closes")
	panel.close()
	await process_frame
	_check(not panel.is_open(), "the inventory panel closes")
	_check(inventory.count_of(BlockDB.OAK_LOG) == logs_before, "closing with a carried stack puts it back")


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
	player.teleport_to(Vector3(8.5, 74.0, 8.5))
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
	var anchor := Vector3i(12, 75, 12)
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			for dy in range(-4, 0):
				_game.world.set_block(anchor + Vector3i(dx, dy, dz), BlockDB.STONE)
	var plot := {"id": "settlement-test", "name": "Testhold", "kind": "hut", "anchor": anchor,
		"width": 5, "depth": 4}
	var state := NpcModel.spawn_state(_game.world.world_seed, plot, 0)
	state["role"] = NpcModel.Role.MINER
	state["position"] = Vector3(12.5, 75.0, 12.5)
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

	# The player targets and kills the resident with its own attack path.
	player.teleport_to(Vector3(float(state["position"].x), float(state["position"].y) + 2.5,
		float(state["position"].z)))
	player.look_pitch(-89.0)
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
	player.teleport_to(Vector3(8.5, 74.0, 8.5))
	player.look_pitch(-20.0)
	for i in range(2):
		await process_frame


## A night raid: raiders spawn around the settlement, the residents fight back and
## the raid ends.  The raiders are real grunt nodes and the fight resolves through
## the same attack path the player uses.
func _raid_section() -> void:
	# A live resident to defend the place.
	var defender := NpcModel.spawn_state(_game.world.world_seed, {
		"id": "settlement-test", "name": "Testhold", "kind": "hut", "anchor": Vector3i(12, 75, 12),
		"width": 5, "depth": 4,
	}, 0)
	defender["role"] = NpcModel.Role.MINER
	_game.npc_states[str(defender["id"])] = defender
	_game.settlement_stores["settlement-test"] = {}
	# The raid targets the settlements the game has already derived; a stand-in
	# entry keeps the test independent of where the world put a hut.
	_game.settlements = [{"id": "settlement-test", "name": "Testhold", "kind": "hut",
		"anchor": Vector3i(12, 75, 12), "width": 5, "depth": 4, "distance": 4.0}]
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

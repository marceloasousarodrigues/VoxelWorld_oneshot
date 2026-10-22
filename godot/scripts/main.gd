extends Node3D

const CHUNK_SIZE := 16
const CHUNK_HALF := CHUNK_SIZE / 2
const SCENARIO_PATH := "res://../prototypes/m17/shared/scenario.json"
const FIXTURE_PATH := "res://../prototypes/m17/shared/fixture/world.json"
const CAPTURE_DIR := "res://../prototypes/m17/results/godot"
const FIXTURE_ADAPTER := preload("res://scripts/core/fixture_adapter.gd")
const AIR := 0
const GRASS := 1
const DIRT := 2
const STONE := 3
const WATER := 4
const MATERIAL_IDS := [GRASS, DIRT, STONE, WATER]
const MATERIAL_NAMES := {GRASS: "Grass", DIRT: "Dirt", STONE: "Stone", WATER: "Water"}
const MATERIAL_COLORS := {
	GRASS: Color("79ad55"),
	DIRT: Color("98704b"),
	STONE: Color("899299"),
	WATER: Color("42b9d6")
}
const FACE_NORMALS := [
	Vector3.RIGHT, Vector3.LEFT, Vector3.UP,
	Vector3.DOWN, Vector3.BACK, Vector3.FORWARD
]
const FACE_CORNERS := [
	[Vector3(0.5, -0.5, -0.5), Vector3(0.5, 0.5, -0.5), Vector3(0.5, 0.5, 0.5), Vector3(0.5, -0.5, 0.5)],
	[Vector3(-0.5, -0.5, 0.5), Vector3(-0.5, 0.5, 0.5), Vector3(-0.5, 0.5, -0.5), Vector3(-0.5, -0.5, -0.5)],
	[Vector3(-0.5, 0.5, 0.5), Vector3(0.5, 0.5, 0.5), Vector3(0.5, 0.5, -0.5), Vector3(-0.5, 0.5, -0.5)],
	[Vector3(-0.5, -0.5, -0.5), Vector3(0.5, -0.5, -0.5), Vector3(0.5, -0.5, 0.5), Vector3(-0.5, -0.5, 0.5)],
	[Vector3(0.5, -0.5, 0.5), Vector3(0.5, 0.5, 0.5), Vector3(-0.5, 0.5, 0.5), Vector3(-0.5, -0.5, 0.5)],
	[Vector3(-0.5, -0.5, -0.5), Vector3(-0.5, 0.5, -0.5), Vector3(0.5, 0.5, -0.5), Vector3(0.5, -0.5, -0.5)]
]
## Godot's front faces wind so the right-hand-rule triangle normal points into
## the solid; the opposite order made every face a back face (hidden surfaces and
## inverted collision normals).
const QUAD_INDICES := [0, 2, 1, 0, 3, 2]
const FACE_SHADES := [1.0, 0.68, 1.14, 0.5, 0.82, 0.92]
const MOVE_SPEED := 7.0
const JUMP_SPEED := 7.0
const GRAVITY := 24.0
const CAMERA_HEIGHT := 1.6
const INTERACTION_RANGE := 6.0
const MOUSE_SENSITIVITY := 0.002

var scenario: Dictionary = {}
var blocks: Dictionary = {}
var chunk_nodes: Dictionary = {}
var materials: Dictionary = {}
var voxel_world: VoxelWorld
var player: CharacterBody3D
var camera: Camera3D
var hud: Label
var selected_material := GRASS
var fixture_hashes: Dictionary = {}
var fixture_metrics: Dictionary = {}
var last_hit_position := Vector3.ZERO
var build_collisions := true
var streaming_enabled := false
var streaming_radius := 3
var chunk_retention_radius := 5
var last_stream_center := Vector2i(2147483647, 2147483647)
var edited_chunks: Dictionary = {}


func _ready() -> void:
	build_collisions = not _has_user_arg("--disable-collisions")
	_load_scenario()
	_load_fixture()
	_create_player()
	_create_materials()
	_create_world()
	if _has_user_arg("--enable-streaming"):
		voxel_world.chunk_created.connect(_create_chunk_rendering)
		voxel_world.chunk_removed.connect(_remove_chunk_rendering)
		streaming_enabled = true
		_refresh_streamed_chunks()
	_create_hud()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	print("M17_READY chunks=%d fixture_chunks=%d selected=grass" % [chunk_nodes.size(), fixture_hashes.size()])
	if _has_user_arg("--capture-on-ready"):
		# Let terrain, shadows and the generated materials finish their first render.
		await get_tree().create_timer(3.0).timeout
		await RenderingServer.frame_post_draw
		_capture("godot-native-slice.png")
		get_tree().quit()


func _has_user_arg(argument: String) -> bool:
	var arguments := OS.get_cmdline_user_args()
	if arguments.has(argument):
		return true
	# Godot treats trailing unknown options as user arguments in documented CLI use.
	for user_argument: String in arguments:
		if user_argument.contains(argument):
			return true
	return false


func _load_scenario() -> void:
	var path := ProjectSettings.globalize_path(SCENARIO_PATH)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Missing shared M17 scenario: %s" % path)
		return
	scenario = JSON.parse_string(file.get_as_text())


func _load_fixture() -> void:
	var path := ProjectSettings.globalize_path(FIXTURE_PATH)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Missing M17 fixture. Run python prototypes/m17/shared/generate_fixture.py")
		return
	voxel_world = VoxelWorld.new(int(scenario.seed))
	var adapter_result: Dictionary = FIXTURE_ADAPTER.load_into_world(voxel_world, scenario, path)
	assert(not adapter_result.is_empty(), "Deterministic shared fixture was validated and adopted")
	fixture_hashes = adapter_result.get("hashes", {})
	fixture_metrics = adapter_result
	for coord: Vector3i in voxel_world.chunks:
		blocks[coord] = voxel_world.chunks[coord].blocks


func _create_materials() -> void:
	for material_id: int in MATERIAL_IDS:
		var material := StandardMaterial3D.new()
		material.albedo_color = MATERIAL_COLORS[material_id]
		material.roughness = 0.92 if material_id != WATER else 0.18
		if material_id == WATER:
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.albedo_color.a = 0.68
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
		else:
			material.cull_mode = BaseMaterial3D.CULL_BACK
		var shader := Shader.new()
		if material_id == WATER:
			shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;
uniform vec4 tint : source_color = vec4(0.12, 0.57, 0.76, 0.70);
uniform float world_scale = 0.24;
varying vec3 world_position;
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 p = (world_position.xz + vec2(world_position.y * 0.17, world_position.y * -0.13)) * world_scale;
	float ripple = 0.045 * sin(p.x * 5.0 + p.y * 3.1) * cos(p.y * 4.3 - p.x * 1.7);
	ALBEDO = clamp(COLOR.rgb * tint.rgb * (0.92 + ripple), vec3(0.0), vec3(1.0));
	ROUGHNESS = 0.16;
	METALLIC = 0.04;
	ALPHA = tint.a;
}
"""
		else:
			shader.code = """
shader_type spatial;
uniform vec4 tint : source_color = vec4(0.5, 0.6, 0.4, 1.0);
uniform float world_scale = 0.37;
varying vec3 world_position;
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec3 p = world_position * world_scale;
	float variation = 0.09 * sin(p.x * 4.71 + p.z * 2.3) * cos(p.z * 5.13 - p.y * 1.7)
		+ 0.035 * sin(dot(floor(p * 1.4), vec3(19.19, 7.37, 31.51)));
	ALBEDO = clamp(COLOR.rgb * tint.rgb * (0.94 + variation), vec3(0.0), vec3(1.0));
	ROUGHNESS = 0.9;
}
"""
		var shader_material := ShaderMaterial.new()
		shader_material.shader = shader
		shader_material.set_shader_parameter("tint", MATERIAL_COLORS[material_id])
		shader_material.render_priority = -1 if material_id == WATER else 0
		materials[material_id] = shader_material


func _create_world() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("2679bb")
	sky_material.sky_horizon_color = Color("c2dcdd")
	sky_material.ground_bottom_color = Color("435c4c")
	sky_material.ground_horizon_color = Color("b2c6b7")
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_sky_contribution = 0.45
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color("a9c8d0")
	environment.fog_density = 0.006
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.name = "GeneratedSun"
	sun.rotation_degrees = Vector3(-52.0, -35.0, 0.0)
	sun.light_color = Color("fff0d2")
	sun.light_energy = 1.45
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(sun)

	for coord: Vector3i in voxel_world.chunks:
		var chunk_key := _chunk_key(coord)
		if not blocks.has(chunk_key):
			push_error("Scenario includes chunk without deterministic fixture data: %s" % chunk_key)
			continue
		_create_chunk_rendering(chunk_key)


	for coord: Vector3i in chunk_nodes:
		_rebuild_chunk(coord)


func _create_player() -> void:
	player = CharacterBody3D.new()
	player.name = "FirstPersonPlayer"
	player.position = Vector3(8.0, 12.0, 8.0)
	player.rotation.y = deg_to_rad(21.0)
	player.floor_snap_length = 0.35
	add_child(player)
	var capsule := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.36
	shape.height = 1.8
	capsule.shape = shape
	capsule.position.y = 0.9
	player.add_child(capsule)
	camera = Camera3D.new()
	camera.name = "FirstPersonCamera"
	camera.position.y = CAMERA_HEIGHT
	camera.rotation.x = deg_to_rad(-18.0)
	camera.fov = 74.0
	player.add_child(camera)


func _create_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	hud = Label.new()
	hud.position = Vector2(18, 16)
	hud.add_theme_color_override("font_color", Color("ffffff"))
	hud.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	hud.add_theme_constant_override("shadow_offset_x", 2)
	hud.add_theme_constant_override("shadow_offset_y", 2)
	canvas.add_child(hud)
	_update_hud("Ready — nine deterministic chunk fixtures")
	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.add_theme_font_size_override("font_size", 24)
	crosshair.add_theme_color_override("font_color", Color.WHITE)
	canvas.add_child(crosshair)


func _update_hud(status: String = "") -> void:
	var prompt := ""
	if not status.is_empty():
		prompt = "\n" + status
	hud.text = (
		"M17  |  GODOT 4.7.2 NATIVE SLICE  |  Seed %d\n" % int(scenario.get("seed", 17017))
		+ "WASD move  •  Space jump  •  Mouse look  •  Esc free/capture cursor\n"
		+ "LMB break  •  RMB place selected  •  1–4 select block  •  Selected: %s  |  Chunks: %d\n" % [MATERIAL_NAMES[selected_material], chunk_nodes.size()]
		+ "Procedural cube  |  [1] Grass  [2] Dirt  [3] Stone  [4] Water"
		+ prompt
	)


func _process(_delta: float) -> void:
	if not is_instance_valid(camera):
		return
	var query := _interaction_query()
	query.collide_with_areas = false
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	last_hit_position = result.get("position", Vector3.ZERO)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	if streaming_enabled:
		var center := Vector2i(floori(player.global_position.x / CHUNK_SIZE), floori(player.global_position.z / CHUNK_SIZE))
		if center != last_stream_center:
			_refresh_streamed_chunks()
	if not player.is_on_floor():
		player.velocity.y -= GRAVITY * delta
	elif Input.is_action_just_pressed("jump"):
		player.velocity.y = JUMP_SPEED
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := player.global_basis * Vector3(input.x, 0.0, input.y)
	player.velocity.x = direction.x * MOVE_SPEED
	player.velocity.z = direction.z * MOVE_SPEED
	player.move_and_slide()


func _interaction_query() -> PhysicsRayQueryParameters3D:
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position + -camera.global_basis.z * INTERACTION_RANGE)
	query.collide_with_areas = false
	query.exclude = [player.get_rid()]
	return query


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		player.rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera.rotation.x = clampf(camera.rotation.x - event.relative.y * MOUSE_SENSITIVITY, deg_to_rad(-88.0), deg_to_rad(88.0))
	elif event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("break_block"):
		_edit_target(false)
	elif event.is_action_pressed("place_block"):
		_edit_target(true)
	elif event.is_action_pressed("select_grass"):
		_select(GRASS)
	elif event.is_action_pressed("select_dirt"):
		_select(DIRT)
	elif event.is_action_pressed("select_stone"):
		_select(STONE)
	elif event.is_action_pressed("select_water"):
		_select(WATER)


func _select(material_id: int) -> void:
	selected_material = material_id
	_update_hud()


func _edit_target(placing: bool) -> void:
	var hit := get_world_3d().direct_space_state.intersect_ray(_interaction_query())
	if hit.is_empty():
		_update_hud("No block in reach")
		return
	var target_position: Vector3 = hit.position + hit.normal * (0.51 if placing else -0.01)
	var target := Vector3i(floori(target_position.x), floori(target_position.y), floori(target_position.z))
	var current := get_block_world(target)
	if placing and current != AIR:
		_update_hud("Target cell is occupied")
		return
	if placing and _player_intersects(target):
		_update_hud("Cannot place a block inside the player")
		return
	if not placing and current == AIR:
		_update_hud("Target block is already empty")
		return
	_set_block_world(target, selected_material if placing else AIR)
	_update_hud("%s %s at (%d, %d, %d)" % ["Placed " + MATERIAL_NAMES[selected_material] if placing else "Broke " + MATERIAL_NAMES.get(current, "block"), "block", target.x, target.y, target.z])
	print("M17_EDIT action=%s position=%s block=%d affected_chunks=%s" % ["place" if placing else "break", target, selected_material if placing else AIR, _affected_chunk_keys(target)])


func _player_intersects(world_position: Vector3i) -> bool:
	var low := player.global_position + Vector3(0.0, 0.05, 0.0)
	var high := player.global_position + Vector3(0.0, 1.78, 0.0)
	return world_position.x + 1.0 > low.x and world_position.x < high.x \
		and world_position.y + 1.0 > low.y and world_position.y < high.y \
		and world_position.z + 1.0 > low.z and world_position.z < high.z


func _set_block_world(world_position: Vector3i, block_id: int) -> void:
	if not streaming_enabled:
		_set_fixture_block(world_position, block_id)
		return
	if not voxel_world.set_block(world_position, block_id):
		_update_hud("Block change could not be applied to a loaded chunk")
		return
	for coord: Vector3i in voxel_world.chunks:
		blocks[coord] = voxel_world.chunks[coord].blocks
		if voxel_world.chunks[coord].mesh_dirty and chunk_nodes.has(coord):
			_rebuild_chunk(coord)


func _set_fixture_block(world_position: Vector3i, block_id: int) -> void:
	if world_position.y < 0 or world_position.y >= CHUNK_SIZE:
		_update_hud("Vertical block position is outside the active chunk")
		return
	var chunk_coord := _chunk_for_world(world_position)
	if not blocks.has(chunk_coord):
		_update_hud("Chunk is not loaded")
		return
	var local := VoxelWorld.world_to_local(world_position)
	var cell_index := ChunkData.cell_index(local.x, local.y, local.z)
	blocks[chunk_coord][cell_index] = block_id
	for coord: Vector3i in _affected_chunk_keys(world_position):
		if chunk_nodes.has(coord):
			_rebuild_chunk(coord)


func _affected_chunk_keys(world_position: Vector3i) -> Array:
	var key := Vector3i(floori(float(world_position.x) / CHUNK_SIZE), 0, floori(float(world_position.z) / CHUNK_SIZE))
	var local_x := posmod(world_position.x, CHUNK_SIZE)
	var local_z := posmod(world_position.z, CHUNK_SIZE)
	var affected: Array = [key]
	if local_x == 0: affected.append(key + Vector3i.LEFT)
	if local_x == CHUNK_SIZE - 1: affected.append(key + Vector3i.RIGHT)
	if local_z == 0: affected.append(key + Vector3i.FORWARD)
	if local_z == CHUNK_SIZE - 1: affected.append(key + Vector3i.BACK)
	return affected


func _chunk_key(coord: Vector3i) -> Vector3i:
	return Vector3i(coord.x, 0, coord.z)


func _create_chunk_rendering(coord: Vector3i) -> void:
	if chunk_nodes.has(coord):
		return
	var chunk := Node3D.new()
	chunk.name = "Chunk_%d_%d_%d" % [coord.x, coord.y, coord.z]
	chunk.position = Vector3(_chunk_origin(coord))
	chunk_nodes[coord] = chunk
	add_child(chunk)
	_rebuild_chunk(coord)
	print("M17_STREAM_CREATE chunk=%s loaded=%d" % [coord, voxel_world.chunks.size()])


func _remove_chunk_rendering(coord: Vector3i) -> void:
	if not chunk_nodes.has(coord):
		return
	var node: Node3D = chunk_nodes[coord]
	chunk_nodes.erase(coord)
	node.free()
	blocks.erase(coord)
	print("M17_STREAM_RELEASE chunk=%s loaded=%d" % [coord, voxel_world.chunks.size()])


func _refresh_streamed_chunks() -> void:
	last_stream_center = Vector2i(floori(player.global_position.x / CHUNK_SIZE), floori(player.global_position.z / CHUNK_SIZE))
	var center := last_stream_center
	var retained: Dictionary = {}
	for z in range(center.y - chunk_retention_radius, center.y + chunk_retention_radius + 1):
		for x in range(center.x - chunk_retention_radius, center.x + chunk_retention_radius + 1):
			retained[Vector3i(x, 0, z)] = true
			if maxi(absi(x - center.x), absi(z - center.y)) <= streaming_radius:
				voxel_world.ensure_chunk(Vector3i(x, 0, z))
	for coord: Vector3i in voxel_world.chunks.keys():
		if not retained.has(coord):
			voxel_world.unload_chunk(coord)
	last_stream_center = center


func _apply_chunk_edits(chunk: ChunkData) -> void:
	var overrides: Dictionary = edited_chunks.get(chunk.coord, {})
	for position: Vector3i in overrides:
		var local := VoxelWorld.world_to_local(position)
		chunk.blocks[ChunkData.cell_index(local.x, local.y, local.z)] = int(overrides[position])
		chunk.edited = true


func _chunk_origin(coord: Vector3i) -> Vector3i:
	return Vector3i(coord.x * CHUNK_SIZE, 0, coord.z * CHUNK_SIZE)


func _chunk_for_world(world_position: Vector3i) -> Vector3i:
	return Vector3i(floori(float(world_position.x) / CHUNK_SIZE), 0, floori(float(world_position.z) / CHUNK_SIZE))


func _mesher_neighbour(chunk: ChunkData, x: int, y: int, z: int, face: int, world_position: Vector3i) -> int:
	var local_offset := Vector3i(roundi(FACE_NORMALS[face].x), roundi(FACE_NORMALS[face].y), roundi(FACE_NORMALS[face].z))
	var neighbor := Vector3i(x, y, z) + local_offset
	if neighbor.x >= 0 and neighbor.x < CHUNK_SIZE and neighbor.y >= 0 and neighbor.y < CHUNK_SIZE and neighbor.z >= 0 and neighbor.z < CHUNK_SIZE:
		return int(chunk.blocks[ChunkData.cell_index(neighbor.x, neighbor.y, neighbor.z)])
	return voxel_world.get_block(world_position + local_offset)


func get_block_world(world_position: Vector3i) -> int:
	if voxel_world != null:
		return voxel_world.get_block(world_position)
	var chunk_coord := _chunk_for_world(world_position)
	if not blocks.has(chunk_coord):
		return AIR
	var local_x := posmod(world_position.x, CHUNK_SIZE)
	var local_y := posmod(world_position.y, CHUNK_SIZE)
	var local_z := posmod(world_position.z, CHUNK_SIZE)
	var cell_index := local_x + CHUNK_SIZE * (local_z + CHUNK_SIZE * local_y)
	return int(blocks[chunk_coord][cell_index])


func build_all_meshes() -> void:
	for coord: Vector3i in chunk_nodes:
		_rebuild_chunk(coord)
	print("M17_MESHES_BUILT chunks=%d" % chunk_nodes.size())


func _rebuild_chunk(coord: Vector3i) -> void:
	var chunk_data: PackedByteArray = blocks[coord]
	var chunk_state: ChunkData = voxel_world.chunks.get(coord, null)
	if chunk_state == null:
		push_error("Cannot mesh missing voxel chunk %s" % coord)
		return
	var arrays_by_material := {}
	for material_id: int in MATERIAL_IDS:
		arrays_by_material[material_id] = {
			Mesh.ARRAY_VERTEX: PackedVector3Array(),
			Mesh.ARRAY_NORMAL: PackedVector3Array(),
			Mesh.ARRAY_COLOR: PackedColorArray(),
			Mesh.ARRAY_INDEX: PackedInt32Array()
		}
	for cell_index: int in range(chunk_data.size()):
		var block_id := int(chunk_data[cell_index])
		if block_id == AIR:
			continue
		var x: int = cell_index % CHUNK_SIZE
		var z: int = floori(float(cell_index) / CHUNK_SIZE) % CHUNK_SIZE
		var y: int = floori(float(cell_index) / (CHUNK_SIZE * CHUNK_SIZE))
		var local_block := Vector3(x, y, z) + Vector3.ONE * 0.5
		var world_block: Vector3i = _chunk_origin(coord) + Vector3i(x, y, z)
		var target_chunk := voxel_world.chunks[coord] as ChunkData
		var local_x := x
		var local_y := y
		var local_z := z
		for face in range(FACE_NORMALS.size()):
			var normal: Vector3 = FACE_NORMALS[face]
			var neighbour_id := _mesher_neighbour(target_chunk, local_x, local_y, local_z, face, world_block)
			if BlockDB.hides_neighbour_face(block_id, neighbour_id):
				continue
			_append_face(arrays_by_material[block_id], local_block, face, block_id)

	var mesh := ArrayMesh.new()
	for material_id: int in MATERIAL_IDS:
		var arrays: Dictionary = arrays_by_material[material_id]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			continue
		# Interleave water and land surfaces so transparent water retains correct sorting.
		var surface_arrays: Array = []
		surface_arrays.resize(Mesh.ARRAY_MAX)
		surface_arrays[Mesh.ARRAY_VERTEX] = arrays[Mesh.ARRAY_VERTEX]
		surface_arrays[Mesh.ARRAY_NORMAL] = arrays[Mesh.ARRAY_NORMAL]
		surface_arrays[Mesh.ARRAY_COLOR] = arrays[Mesh.ARRAY_COLOR]
		surface_arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, materials[material_id])
		var mesh_material: Material = mesh.surface_get_material(mesh.get_surface_count() - 1)
		if mesh_material is ShaderMaterial:
			mesh_material.set_shader_parameter("tint", MATERIAL_COLORS[material_id])
	var chunk_node: Node3D = chunk_nodes[coord]
	for child in chunk_node.get_children():
		child.free()
	if mesh.get_surface_count() > 0:
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = "ChunkMesh"
		mesh_instance.mesh = mesh
		chunk_node.add_child(mesh_instance)
		if build_collisions:
			_add_collision(mesh, chunk_node)
	if voxel_world != null and voxel_world.chunks.has(coord):
		voxel_world.chunks[coord].mesh_dirty = false
		voxel_world.chunks[coord].collision_dirty = false


func _append_face(arrays: Dictionary, origin: Vector3, face: int, material_id: int) -> void:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var corners: Array = FACE_CORNERS[face]
	var base := vertices.size()
	var tone: float = FACE_SHADES[face]
	for corner_index: int in range(4):
		vertices.append(origin + corners[corner_index])
		normals.append(FACE_NORMALS[face])
		var face_color := Color.WHITE
		var is_side := face == 0 or face == 1 or face == 4 or face == 5
		if material_id == GRASS and is_side and origin.y < 4.0:
			face_color = Color("98704b")
		colors.append(face_color * tone)
	for index: int in QUAD_INDICES:
		indices.append(base + index)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices


func _add_collision(mesh: ArrayMesh, parent: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "ChunkCollision"
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	parent.add_child(body)


func _capture(filename: String) -> void:
	var capture_directory := ProjectSettings.globalize_path(CAPTURE_DIR)
	if not DirAccess.dir_exists_absolute(capture_directory):
		DirAccess.make_dir_recursive_absolute(capture_directory)
	var path := capture_directory.path_join(filename)
	var error := get_viewport().get_texture().get_image().save_png(path)
	if error == OK:
		print("M17_SCREENSHOT_SAVED %s" % ProjectSettings.globalize_path(path))
	else:
		push_error("Could not save prototype screenshot %s (error %d)" % [path, error])

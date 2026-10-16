class_name VoxelPlayer
extends CharacterBody3D

## First-person voxel player: mouse look, WASD movement with gravity and jumping,
## and block interaction driven by exact voxel traversal (`VoxelRay`) rather than
## physics probing, so targeting keeps working while collision meshes rebuild.
##
## Interaction is deliberately decoupled: this node never mutates the inventory
## or the HUD directly, it emits signals the game layer reacts to.

signal block_broken(world_position: Vector3i, block_id: int, drop: int)
signal block_placed(world_position: Vector3i, block_id: int)
signal target_changed(hit: Dictionary)
signal interaction_failed(reason: String)
signal fly_changed(enabled: bool)

const REACH := 6.0
const BODY_HEIGHT := 1.8
const BODY_RADIUS := 0.34
const EYE_HEIGHT := 1.62

@export var move_speed := 5.4
@export var sprint_multiplier := 1.8
@export var jump_velocity := 8.9
@export var gravity := 24.0
@export var mouse_sensitivity := 0.0022
@export var fly_speed := 18.0
@export var repeat_interval := 0.2
@export var reach := REACH

var world: VoxelWorld
var inventory: Inventory
var camera: Camera3D
var marker: MeshInstance3D

var flying := false
var can_interact := true

var _pitch := 0.0
var _break_cooldown := 0.0
var _place_cooldown := 0.0
var _hit: Dictionary = {"hit": false}
var _last_reported_key := ""


func _ready() -> void:
	_build_body()
	_build_camera()
	_build_marker()


func _build_body() -> void:
	collision_layer = 1
	collision_mask = 1
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(52.0)
	slide_on_ceiling = true
	var shape := CapsuleShape3D.new()
	shape.radius = BODY_RADIUS
	shape.height = BODY_HEIGHT
	var collision := CollisionShape3D.new()
	collision.name = "Body"
	collision.shape = shape
	collision.position.y = BODY_HEIGHT * 0.5
	add_child(collision)


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.name = "Eye"
	camera.position.y = EYE_HEIGHT
	camera.fov = 76.0
	camera.near = 0.05
	camera.far = 800.0
	add_child(camera)
	camera.make_current()


## A thin 12-edge box outline that marks the targeted block.  It is a top-level
## node so the player's rotation never tilts it.
func _build_marker() -> void:
	var half := 0.502
	var corners: Array[Vector3] = []
	for y in [-half, half]:
		for z in [-half, half]:
			for x in [-half, half]:
				corners.append(Vector3(x, y, z))
	var edges := [
		[0, 1], [2, 3], [4, 5], [6, 7],
		[0, 2], [1, 3], [4, 6], [5, 7],
		[0, 4], [1, 5], [2, 6], [3, 7],
	]
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.05, 0.05, 0.06, 0.85)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for edge: Array in edges:
		mesh.surface_add_vertex(corners[int(edge[0])])
		mesh.surface_add_vertex(corners[int(edge[1])])
	mesh.surface_end()
	marker = MeshInstance3D.new()
	marker.name = "TargetMarker"
	marker.mesh = mesh
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.top_level = true
	marker.visible = false
	add_child(marker)


# --- spawn / teleport ----------------------------------------------------

## Places the player with its feet on top of the first solid block in a column.
func spawn_on_column(world_x: int, world_z: int, search_top: int = 110) -> void:
	var ground := search_top
	while ground > 1 and not world.is_solid(Vector3i(world_x, ground, world_z)):
		ground -= 1
	var spawn := Vector3(world_x + 0.5, float(ground) + 1.05, world_z + 0.5)
	teleport_to(spawn)


func teleport_to(world_position: Vector3) -> void:
	global_position = world_position
	velocity = Vector3.ZERO


func look_yaw(degrees: float) -> void:
	rotation.y = deg_to_rad(degrees)


func look_pitch(degrees: float) -> void:
	_pitch = deg_to_rad(degrees)
	if camera != null:
		camera.rotation.x = _pitch


func eye_position() -> Vector3:
	return camera.global_position if camera != null else global_position + Vector3.UP * EYE_HEIGHT


## Current yaw and pitch in degrees, for diagnostics and capture breadcrumbs.
func look_angles() -> Vector2:
	var pitch := camera.rotation.x if camera != null else _pitch
	return Vector2(rad_to_deg(rotation.y), rad_to_deg(pitch))


func look_basis() -> Basis:
	return Basis(Vector3.UP, rotation.y)


# --- frame loop ----------------------------------------------------------

func _process(delta: float) -> void:
	_break_cooldown = maxf(0.0, _break_cooldown - delta)
	_place_cooldown = maxf(0.0, _place_cooldown - delta)
	_update_target()
	if not can_interact or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if Input.is_action_pressed("break_block") and _break_cooldown <= 0.0:
		_break_cooldown = repeat_interval
		break_target()
	elif Input.is_action_pressed("place_block") and _place_cooldown <= 0.0:
		_place_cooldown = repeat_interval
		place_selected()


func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var basis := look_basis()
	var direction := basis * Vector3(input.x, 0.0, input.y)
	var wants_sprint := Input.is_action_pressed("sprint")
	if flying:
		var vertical := 0.0
		if Input.is_action_pressed("jump"):
			vertical += 1.0
		if Input.is_action_pressed("crouch"):
			vertical -= 1.0
		var speed := fly_speed * (sprint_multiplier if wants_sprint else 1.0)
		velocity = (direction + Vector3.UP * clampf(vertical, -1.0, 1.0)) * speed
	else:
		var speed := move_speed * (sprint_multiplier if wants_sprint else 1.0)
		if not is_on_floor():
			speed *= 0.62
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		if is_on_floor():
			if Input.is_action_just_pressed("jump"):
				velocity.y = jump_velocity
			elif velocity.y < 0.0:
				velocity.y = -1.0
		else:
			velocity.y -= gravity * delta
	move_and_slide()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= event.relative.x * mouse_sensitivity
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, deg_to_rad(-89.5), deg_to_rad(89.5))
		camera.rotation.x = _pitch


func toggle_fly() -> void:
	flying = not flying
	velocity = Vector3.ZERO
	fly_changed.emit(flying)


# --- targeting -----------------------------------------------------------

func _update_target() -> void:
	if world == null or camera == null:
		return
	var found := VoxelRay.cast(world, camera.global_position, -camera.global_basis.z, reach)
	_hit = found
	if found.get("hit", false):
		var cell: Vector3i = found["block"]
		marker.global_position = Vector3(cell) + Vector3.ONE * 0.5
		marker.visible = true
	else:
		marker.visible = false
	var key := "%s|%s" % [str(found.get("hit", false)), str(found.get("block", Vector3i.ZERO))]
	if key != _last_reported_key:
		_last_reported_key = key
		target_changed.emit(found)


func target() -> Dictionary:
	return _hit


# --- interaction ---------------------------------------------------------

func break_target() -> bool:
	var hit := target()
	if not hit.get("hit", false):
		interaction_failed.emit("No block in reach")
		return false
	var cell: Vector3i = hit["block"]
	var block_id: int = hit["block_id"]
	if not BlockDB.is_breakable(block_id):
		interaction_failed.emit("%s cannot be mined" % BlockDB.name_of(block_id))
		return false
	if not world.set_block(cell, BlockDB.AIR):
		interaction_failed.emit("That block is outside the loaded world")
		return false
	block_broken.emit(cell, block_id, BlockDB.drop_of(block_id))
	_update_target()
	return true


func place_selected() -> bool:
	var hit := target()
	if not hit.get("hit", false):
		interaction_failed.emit("Nothing to build against")
		return false
	if inventory == null:
		return false
	var block_id := inventory.selected_block()
	if block_id == BlockDB.AIR:
		interaction_failed.emit("Hotbar slot is empty")
		return false
	var normal: Vector3i = hit["normal"]
	var cell: Vector3i = hit["block"] + normal
	if not VoxelWorld.in_world_vertical(cell.y):
		interaction_failed.emit("Outside the buildable height")
		return false
	var existing := world.get_block(cell)
	if existing != BlockDB.AIR and not BlockDB.is_liquid(existing):
		interaction_failed.emit("That space is occupied")
		return false
	if cell_intersects_body(cell):
		interaction_failed.emit("Cannot build inside yourself")
		return false
	if not world.set_block(cell, block_id):
		interaction_failed.emit("That block is outside the loaded world")
		return false
	block_placed.emit(cell, block_id)
	_update_target()
	return true


## True when the given world cell overlaps the player's collision volume.
func cell_intersects_body(cell: Vector3i) -> bool:
	var feet := global_position
	var top := feet.y + BODY_HEIGHT
	return float(cell.x) + 1.0 > feet.x - BODY_RADIUS and float(cell.x) < feet.x + BODY_RADIUS \
		and float(cell.y) + 1.0 > feet.y + 0.05 and float(cell.y) < top \
		and float(cell.z) + 1.0 > feet.z - BODY_RADIUS and float(cell.z) < feet.z + BODY_RADIUS


func is_submerged() -> bool:
	if world == null:
		return false
	return world.get_block(Vector3i(floori(eye_position().x), floori(eye_position().y), floori(eye_position().z))) == BlockDB.WATER

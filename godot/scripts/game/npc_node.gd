class_name NpcNode
extends CharacterBody3D

## Scene representation of one settlement resident.
##
## The rules live in `scripts/core/npc.gd`; this node owns the visual body, the
## physics (gravity and collision, so a resident walks over the terrain instead of
## hovering), a name plate, and the hit reactions the game reacts to.

signal killed(npc: NpcNode)

const MODEL := preload("res://scripts/core/npc.gd")
const BODY_COLOR := Color(0.42, 0.36, 0.62)
const TUNIC_COLOR := Color(0.42, 0.62, 0.40)
const MINER_COLOR := Color(0.36, 0.48, 0.72)
const HURT_COLOR := Color(0.85, 0.55, 0.55)
const GRAVITY := 24.0
const WORK_BOB_SPEED := 9.0

var state: Dictionary
var world: VoxelWorld

var _body_mesh: MeshInstance3D
var _bob_phase := 0.0
var _stuck := 0.0


func configure(npc_state: Dictionary, voxel_world: VoxelWorld) -> void:
	state = npc_state
	world = voxel_world
	_build_shape()
	# `position` rather than `global_position`: the node may be configured before it
	# is added to the tree, and its parent sits at the world origin.
	position = Vector3(float(npc_state["position"].x), float(npc_state["position"].y) + 0.2,
		float(npc_state["position"].z))


func _build_shape() -> void:
	collision_layer = 2
	collision_mask = 1
	var body_shape := CapsuleShape3D.new()
	body_shape.radius = 0.34
	body_shape.height = 1.5
	var collider := CollisionShape3D.new()
	collider.shape = body_shape
	collider.position.y = 0.75
	add_child(collider)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.82, 0.68, 0.55)
	skin.roughness = 0.9
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = BODY_COLOR
	cloth.roughness = 0.95
	# Residents are told apart by their tunic: woodcutters wear green, miners blue.
	var tunic := StandardMaterial3D.new()
	tunic.albedo_color = TUNIC_COLOR if int(state.get("role", 0)) == MODEL.Role.WOODCUTTER else MINER_COLOR
	tunic.roughness = 0.95
	_body_mesh = _part("Body", Vector3(0.0, 0.95, 0.0), Vector3(0.56, 1.0, 0.34), tunic)
	_part("Head", Vector3(0.0, 1.62, 0.0), Vector3(0.44, 0.44, 0.4), skin)
	_part("Hat", Vector3(0.0, 1.84, 0.0), Vector3(0.5, 0.12, 0.46), tunic)
	for x in [-0.38, 0.38]:
		_part("Arm", Vector3(x, 1.0, -0.14), Vector3(0.16, 0.66, 0.16), skin)
	for x in [-0.16, 0.16]:
		_part("Leg", Vector3(x, 0.24, 0.0), Vector3(0.19, 0.48, 0.19), cloth)
	add_to_group("npc")


func _part(part_name: String, offset: Vector3, dimensions: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	var node := MeshInstance3D.new()
	node.name = part_name
	node.mesh = mesh
	node.material_override = material
	node.position = offset
	add_child(node)
	return node





## True while this resident is alive.
func is_alive() -> bool:
	return not state.is_empty() and bool(state.get("alive", false))


func _physics_process(delta: float) -> void:
	if state.is_empty() or not is_alive():
		return
	# The model decides where the resident wants to be in x/z; physics resolves y,
	# so a resident walks the terrain, steps over slopes and cannot hover.
	var destination := Vector3(float(state["position"].x), global_position.y, float(state["position"].z))
	var to_destination := Vector3(destination.x - global_position.x, 0.0, destination.z - global_position.z)
	if to_destination.length() > 0.08:
		var direction := to_destination.normalized()
		velocity.x = direction.x * MODEL.WALK_SPEED
		velocity.z = direction.z * MODEL.WALK_SPEED
		rotation.y = atan2(-direction.x, -direction.z)
		# A resident that cannot make progress (a wall, a fence) asks the model
		# for other work instead of pushing into it forever.
		if to_destination.length() > 1.4 and velocity.length() < MODEL.WALK_SPEED * 0.5:
			_stuck += delta
			if _stuck > 1.5:
				_stuck = 0.0
				state["task"] = MODEL.Task.SEEK
				state["target"] = MODEL.NO_CELL
		else:
			_stuck = 0.0
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	if is_on_floor():
		velocity.y = -1.0
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	# Work has a little animation so a resident that is gathering reads as busy.
	var working := int(state.get("task", MODEL.Task.SEEK)) == MODEL.Task.WORK
	_bob_phase += delta * (WORK_BOB_SPEED if working else 3.0)
	_body_mesh.position.y = 0.95 + absf(sin(_bob_phase)) * (0.05 if working else 0.02)


## Applies one hit from the player.  Returns true when this killed the resident.
func apply_hit(damage: int = 1) -> bool:
	var died := MODEL.damage(state, float(damage))
	if not died:
		var material := _body_mesh.material_override as StandardMaterial3D
		material.albedo_color = HURT_COLOR
		get_tree().create_timer(0.18).timeout.connect(func() -> void:
			if is_instance_valid(_body_mesh) and is_instance_valid(self):
				(_body_mesh.material_override as StandardMaterial3D).albedo_color = BODY_COLOR)
	return died


## Called by the game once the resident is dead so its drops are placed.
func die() -> void:
	killed.emit(self)

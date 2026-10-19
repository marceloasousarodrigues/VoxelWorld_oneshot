class_name HostileCreature
extends CharacterBody3D

## Primitive scene representation of one hostile "grunt".  All rules (chase,
## attack cadence, damage, drops) come from the node-free
## `scripts/core/hostile_creatures.gd`; this node owns only the visual body, the
## voxel-following movement and the signals the game reacts to.

signal killed(creature: HostileCreature)
signal attacked_player(amount: float)

const MODEL := preload("res://scripts/core/hostile_creatures.gd")
const BODY_COLOR := Color(0.22, 0.30, 0.20)
const HURT_COLOR := Color(0.45, 0.58, 0.36)

var state: Dictionary
var world: VoxelWorld
var target: Node3D
## Loot produced by the lethal hit, awarded once by the game layer.
var pending_loot: Array = []

var _cooldown := 0.0
var _bob_phase := 0.0
var _body_mesh: MeshInstance3D


func configure(creature_state: Dictionary, voxel_world: VoxelWorld, target_node: Node3D = null) -> void:
	state = creature_state.duplicate(true)
	world = voxel_world
	target = target_node
	position = state.position
	_build_shape()


func _build_shape() -> void:
	collision_layer = 2
	collision_mask = 1
	var body_shape := CapsuleShape3D.new()
	body_shape.radius = 0.35
	body_shape.height = 1.55
	var collider := CollisionShape3D.new()
	collider.shape = body_shape
	collider.position.y = 0.78
	add_child(collider)
	var material := StandardMaterial3D.new()
	material.albedo_color = BODY_COLOR
	material.roughness = 0.95
	_body_mesh = _part("Body", Vector3(0.0, 0.95, 0.0), Vector3(0.62, 1.05, 0.36), material)
	_part("Head", Vector3(0.0, 1.65, 0.0), Vector3(0.46, 0.46, 0.42), material)
	for x in [-0.42, 0.42]:
		_part("Arm", Vector3(x, 1.05, -0.18), Vector3(0.18, 0.72, 0.18), material)
	for x in [-0.17, 0.17]:
		_part("Leg", Vector3(x, 0.24, 0.0), Vector3(0.2, 0.48, 0.2), material)
	var eyes := StandardMaterial3D.new()
	eyes.albedo_color = Color(0.85, 0.25, 0.18)
	eyes.emission_enabled = true
	eyes.emission = Color(0.9, 0.2, 0.1)
	eyes.emission_energy_multiplier = 1.4
	_part("EyeL", Vector3(-0.11, 1.66, -0.22), Vector3(0.08, 0.06, 0.04), eyes)
	_part("EyeR", Vector3(0.11, 1.66, -0.22), Vector3(0.08, 0.06, 0.04), eyes)
	add_to_group("hostile_creature")


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


func is_alive() -> bool:
	return bool(state.get("alive", false))


func _physics_process(delta: float) -> void:
	if not is_alive() or world == null or target == null or not is_instance_valid(target):
		return
	var model = MODEL.new(world.world_seed)
	var destination: Vector3 = model.chase_destination(world, global_position, target.global_position, delta)
	if not destination.is_equal_approx(global_position):
		var step := destination - global_position
		rotation.y = atan2(-step.x, -step.z)
		global_position = destination
	var flat := Vector2(target.global_position.x - global_position.x, target.global_position.z - global_position.z)
	var attack: Dictionary = model.attack_step(flat.length() <= MODEL.ATTACK_RANGE, _cooldown, delta)
	_cooldown = float(attack["cooldown"])
	if float(attack["damage"]) > 0.0:
		attacked_player.emit(float(attack["damage"]))
	_bob_phase += delta * 7.0
	_body_mesh.position.y = 0.95 + absf(sin(_bob_phase)) * 0.03


## Applies one player hit; returns the number of drops when this kills it.
func apply_hit(damage: int = 1) -> int:
	var result: Dictionary = MODEL.new(world.world_seed).damage(state, damage)
	state = result.creature
	if bool(result.alive):
		var mat := _body_mesh.material_override as StandardMaterial3D
		mat.albedo_color = HURT_COLOR
		get_tree().create_timer(0.18).timeout.connect(func() -> void:
			if is_instance_valid(_body_mesh) and is_instance_valid(self):
				(_body_mesh.material_override as StandardMaterial3D).albedo_color = BODY_COLOR)
	else:
		pending_loot = (result.get("loot", []) as Array).duplicate()
		killed.emit(self)
	return int(result.drops)


## Returns and clears the loot of the lethal hit (awarded once).
func take_loot() -> Array:
	var loot := pending_loot.duplicate(true)
	pending_loot.clear()
	return loot

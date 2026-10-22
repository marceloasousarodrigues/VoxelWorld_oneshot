class_name PassiveCreature
extends CharacterBody3D

signal killed(creature: PassiveCreature)

const MODEL := preload("res://scripts/core/passive_creatures.gd")

var state: Dictionary
var world: VoxelWorld
## Loot produced by the lethal hit, awarded once by the game layer.
var pending_loot: Array = []
var _wander_target := Vector3.ZERO
var _wander_timer := 0.0
var _hop_phase := 0.0
var _body_mesh: MeshInstance3D

func configure(creature_state: Dictionary, voxel_world: VoxelWorld) -> void:
	state = creature_state.duplicate(true)
	world = voxel_world
	position = state.position
	_build_shape()

func _build_shape() -> void:
	collision_layer = 2
	collision_mask = 1
	var body_shape := CapsuleShape3D.new()
	body_shape.radius = 0.38
	body_shape.height = 0.9
	var collider := CollisionShape3D.new()
	collider.shape = body_shape
	collider.position.y = 0.45
	add_child(collider)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.48, 0.24, 0.12)
	material.roughness = 0.9
	_body_mesh = _part("Body", Vector3(0.0, 0.48, 0.0), Vector3(0.92, 0.56, 0.52), material)
	_part("Head", Vector3(0.0, 0.65, -0.45), Vector3(0.48, 0.48, 0.43), material)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.16, 0.09, 0.06)
	_part("Snout", Vector3(0.0, 0.55, -0.70), Vector3(0.26, 0.18, 0.18), dark)
	for x in [-0.24, 0.24]:
		for z in [-0.19, 0.19]:
			_part("Leg", Vector3(x, 0.16, z), Vector3(0.16, 0.34, 0.16), dark)
	add_to_group("passive_creature")

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

func _physics_process(delta: float) -> void:
	if not bool(state.get("alive", false)) or world == null:
		return
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_choose_target()
	var destination: Vector3 = MODEL.new(world.world_seed).wander_destination(world, global_position, _wander_target, delta)
	var step := destination - global_position
	if step.length_squared() > 0.00001:
		rotation.y = atan2(-step.x, -step.z)
		global_position = destination
	_hop_phase += delta * 5.0
	_body_mesh.position.y = 0.48 + absf(sin(_hop_phase)) * 0.035

func _choose_target() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(state.id) * 104729 + int(floor(global_position.x * 13.0)) * 8191 + int(floor(global_position.z * 17.0))
	var direction := Vector2.from_angle(rng.randf_range(0.0, TAU))
	var distance := rng.randf_range(2.0, 6.0)
	_wander_target = global_position + Vector3(direction.x * distance, 0.0, direction.y * distance)
	_wander_timer = rng.randf_range(2.5, 5.0)

func apply_hit(damage: int = 1) -> int:
	var result: Dictionary = MODEL.new(world.world_seed).damage(state, damage)
	state = result.creature
	if bool(result.alive):
		var mat := _body_mesh.material_override as StandardMaterial3D
		mat.albedo_color = Color(0.73, 0.36, 0.21)
		get_tree().create_timer(0.18).timeout.connect(func() -> void:
			if is_instance_valid(_body_mesh) and is_instance_valid(self):
				(_body_mesh.material_override as StandardMaterial3D).albedo_color = Color(0.48, 0.24, 0.12))
	else:
		pending_loot = (result.get("loot", []) as Array).duplicate()
		killed.emit(self)
	return int(result.drops)


## Returns and clears the loot of the lethal hit, so the kill can only ever be
## awarded once even if a second signal arrives.
func take_loot() -> Array:
	var loot := pending_loot.duplicate(true)
	pending_loot.clear()
	return loot

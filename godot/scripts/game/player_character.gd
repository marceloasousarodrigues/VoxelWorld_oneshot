class_name PlayerCharacter
extends Node3D

## The player's stylised voxel body, shared by the third-person camera and the
## inventory Character preview.
##
## The proportions and palette deliberately extend the existing M40 preview: a
## 0.56 m torso, a 0.46 m head and articulated arms/legs.  The second visual pass
## adds the silhouette details that matter from behind (a framed backpack and
## bedroll, belt and side pouches, a shaped tunic hem, layered hair and boot
## soles) without turning the character into a different art style.  There is no
## equipment system in VoxelWorld, so no armour is invented; the actually held
## item is shown in the right hand.

const HeldItemVisualScript = preload("res://scripts/game/held_item_visual.gd")
const Presentation = preload("res://scripts/game/item_presentation.gd")

const SKIN := Color(0.70, 0.49, 0.34)
const SKIN_SHADOW := Color(0.54, 0.35, 0.23)
const HAIR := Color(0.24, 0.15, 0.09)
const HAIR_LIGHT := Color(0.33, 0.21, 0.12)
const TUNIC := Color(0.84, 0.78, 0.64)
const TUNIC_SHADE := Color(0.73, 0.67, 0.53)
const BELT := Color(0.33, 0.22, 0.13)
const LEATHER := Color(0.30, 0.20, 0.12)
const LEATHER_LIGHT := Color(0.43, 0.28, 0.16)
const CANVAS := Color(0.46, 0.34, 0.20)
const CANVAS_LIGHT := Color(0.55, 0.42, 0.26)
const PANTS := Color(0.42, 0.32, 0.22)
const BOOTS := Color(0.22, 0.15, 0.10)
const BOOT_SOLE := Color(0.14, 0.10, 0.07)
const EYE := Color(0.09, 0.07, 0.06)

const SWING_DURATION := 0.34
## The right arm hangs slightly away from the torso so the held tool clears the
## body in the rear view.  This is a pose, not a camera trick: the hand, arm and
## tool all move together, and the shared arm swing still starts from here.
const ARM_OUT := 0.24

var _right_arm: Node3D
var _left_arm: Node3D
var _right_leg: Node3D
var _left_leg: Node3D
var _held_root: Node3D
var _hand_material: StandardMaterial3D
var _held_item := BlockDB.AIR
var _held_library: TextureLibrary
var _walk_phase := 0.0
var _walk_weight := 0.0
var _swing_time := 0.0
var _idle_time := 0.0


func _init() -> void:
	_build()


func _build() -> void:
	# Head, shaped hair and face.
	_box("Head", Vector3(0.46, 0.46, 0.46), Vector3(0.0, 1.77, 0.0), SKIN)
	_box("Jaw", Vector3(0.42, 0.09, 0.44), Vector3(0.0, 1.585, 0.0), SKIN_SHADOW)
	_box("HairTop", Vector3(0.50, 0.13, 0.50), Vector3(0.0, 1.995, 0.0), HAIR)
	_box("HairBack", Vector3(0.50, 0.44, 0.12), Vector3(0.0, 1.75, -0.215), HAIR)
	_box("HairLeft", Vector3(0.05, 0.25, 0.44), Vector3(-0.225, 1.885, 0.0), HAIR)
	_box("HairRight", Vector3(0.05, 0.25, 0.44), Vector3(0.225, 1.885, 0.0), HAIR)
	_box("HairFringe", Vector3(0.46, 0.09, 0.045), Vector3(0.0, 1.955, 0.235), HAIR)
	_box("HairTuftLeft", Vector3(0.11, 0.07, 0.16), Vector3(-0.16, 2.06, 0.06), HAIR_LIGHT)
	_box("HairTuftRight", Vector3(0.09, 0.055, 0.13), Vector3(0.13, 2.05, -0.04), HAIR)
	_box("HairSideburnLeft", Vector3(0.035, 0.13, 0.09), Vector3(-0.232, 1.82, 0.045), HAIR)
	_box("HairSideburnRight", Vector3(0.035, 0.13, 0.09), Vector3(0.232, 1.82, 0.045), HAIR)
	_box("EarLeft", Vector3(0.035, 0.10, 0.08), Vector3(-0.248, 1.76, 0.0), SKIN_SHADOW)
	_box("EarRight", Vector3(0.035, 0.10, 0.08), Vector3(0.248, 1.76, 0.0), SKIN_SHADOW)
	_box("EyeLeft", Vector3(0.075, 0.085, 0.025), Vector3(-0.100, 1.795, 0.241), EYE)
	_box("EyeRight", Vector3(0.075, 0.085, 0.025), Vector3(0.100, 1.795, 0.241), EYE)
	_box("BrowLeft", Vector3(0.095, 0.025, 0.022), Vector3(-0.100, 1.862, 0.242), HAIR)
	_box("BrowRight", Vector3(0.095, 0.025, 0.022), Vector3(0.100, 1.862, 0.242), HAIR)
	_box("Nose", Vector3(0.055, 0.075, 0.045), Vector3(0.0, 1.745, 0.250), SKIN_SHADOW)
	_box("Mouth", Vector3(0.13, 0.028, 0.020), Vector3(0.0, 1.675, 0.242), Color(0.42, 0.25, 0.21))
	_box("Neck", Vector3(0.18, 0.10, 0.18), Vector3(0.0, 1.49, 0.0), SKIN_SHADOW)

	# Torso with a layered hem and a visible belt.
	_box("Tunic", Vector3(0.56, 0.66, 0.32), Vector3(0.0, 1.13, 0.0), TUNIC)
	_box("TunicFront", Vector3(0.34, 0.58, 0.025), Vector3(0.0, 1.15, 0.169), TUNIC_SHADE)
	_box("TunicHem", Vector3(0.60, 0.13, 0.36), Vector3(0.0, 0.815, 0.0), TUNIC)
	_box("TunicHemShade", Vector3(0.60, 0.035, 0.365), Vector3(0.0, 0.755, 0.0), TUNIC_SHADE)
	_box("Collar", Vector3(0.35, 0.07, 0.35), Vector3(0.0, 1.445, 0.0), TUNIC_SHADE)
	_box("Belt", Vector3(0.58, 0.09, 0.34), Vector3(0.0, 0.88, 0.0), BELT)
	_box("Buckle", Vector3(0.10, 0.075, 0.030), Vector3(0.0, 0.88, 0.180), Color(0.78, 0.66, 0.36))

	# Backpack: the dominant rear-view silhouette.  Frame, canvas body, flap,
	# shoulder straps, bedroll and side pouches all read from the third-person
	# camera without adding a single texture.
	_box("PackBody", Vector3(0.40, 0.42, 0.17), Vector3(0.0, 1.12, -0.245), CANVAS)
	_box("PackFlap", Vector3(0.38, 0.15, 0.035), Vector3(0.0, 1.305, -0.333), CANVAS_LIGHT)
	_box("PackFlapEdge", Vector3(0.34, 0.035, 0.028), Vector3(0.0, 1.245, -0.342), LEATHER)
	_box("PackFrame", Vector3(0.42, 0.46, 0.035), Vector3(0.0, 1.12, -0.165), LEATHER)
	for side in [-1.0, 1.0]:
		_box("PackStrap", Vector3(0.065, 0.40, 0.025),
			Vector3(0.145 * side, 1.19, -0.190), LEATHER_LIGHT)
		_box("PackStrapBuckle", Vector3(0.075, 0.045, 0.035),
			Vector3(0.145 * side, 1.05, -0.190), Color(0.72, 0.60, 0.34))
		_box("PackPouch", Vector3(0.095, 0.145, 0.115),
			Vector3(0.245 * side, 1.01, -0.235), LEATHER)
		_box("PackPouchFlap", Vector3(0.105, 0.040, 0.125),
			Vector3(0.245 * side, 1.075, -0.235), LEATHER_LIGHT)
	_box("Bedroll", Vector3(0.42, 0.13, 0.13), Vector3(0.0, 1.365, -0.270), Color(0.50, 0.30, 0.22))
	_box("BedrollStrap", Vector3(0.035, 0.145, 0.145), Vector3(-0.10, 1.365, -0.270), LEATHER)
	_box("BedrollStrap2", Vector3(0.035, 0.145, 0.145), Vector3(0.10, 1.365, -0.270), LEATHER)

	# Articulated arms: the shoulder pivot sits where the old fixed arm's top was.
	_right_arm = _pivot("RightArm", Vector3(0.42, 1.42, 0.0))
	_right_arm.add_child(_box_node("SleeveRight", Vector3(0.18, 0.40, 0.19),
		Vector3(0.0, -0.17, 0.0), TUNIC))
	_right_arm.add_child(_box_node("CuffRight", Vector3(0.185, 0.07, 0.195),
		Vector3(0.0, -0.39, 0.0), TUNIC_SHADE))
	_right_arm.add_child(_box_node("ArmRight", Vector3(0.15, 0.18, 0.16),
		Vector3(0.0, -0.51, 0.0), SKIN))
	_hand_material = _material(SKIN)
	_right_arm.add_child(_box_node("HandRight", Vector3(0.16, 0.14, 0.18),
		Vector3(0.0, -0.62, 0.0), SKIN, _hand_material))
	_right_arm.add_child(_box_node("ThumbRight", Vector3(0.045, 0.075, 0.07),
		Vector3(-0.082, -0.605, 0.06), SKIN))
	_left_arm = _pivot("LeftArm", Vector3(-0.42, 1.42, 0.0))
	_left_arm.add_child(_box_node("SleeveLeft", Vector3(0.18, 0.40, 0.19),
		Vector3(0.0, -0.17, 0.0), TUNIC))
	_left_arm.add_child(_box_node("CuffLeft", Vector3(0.185, 0.07, 0.195),
		Vector3(0.0, -0.39, 0.0), TUNIC_SHADE))
	_left_arm.add_child(_box_node("ArmLeft", Vector3(0.15, 0.18, 0.16),
		Vector3(0.0, -0.51, 0.0), SKIN))
	_left_arm.add_child(_box_node("HandLeft", Vector3(0.16, 0.14, 0.18),
		Vector3(0.0, -0.62, 0.0), SKIN))

	_held_root = Node3D.new()
	_held_root.name = "HeldItem"
	# The grip is in the hand.  The item's +Y points up its handle, so the
	# per-item pose below is relative to the hanging arm rather than to the world.
	_held_root.position = Vector3(0.0, -0.625, -0.085)
	_right_arm.add_child(_held_root)

	# Articulated legs with cuffs and distinct soles.
	_right_leg = _pivot("RightLeg", Vector3(0.15, 0.78, 0.0))
	_right_leg.add_child(_box_node("LegRight", Vector3(0.22, 0.62, 0.24),
		Vector3(0.0, -0.33, 0.0), PANTS))
	_right_leg.add_child(_box_node("BootRight", Vector3(0.24, 0.14, 0.29),
		Vector3(0.0, -0.68, 0.02), BOOTS))
	_right_leg.add_child(_box_node("SoleRight", Vector3(0.25, 0.035, 0.31),
		Vector3(0.0, -0.755, 0.03), BOOT_SOLE))
	_left_leg = _pivot("LeftLeg", Vector3(-0.15, 0.78, 0.0))
	_left_leg.add_child(_box_node("LegLeft", Vector3(0.22, 0.62, 0.24),
		Vector3(0.0, -0.33, 0.0), PANTS))
	_left_leg.add_child(_box_node("BootLeft", Vector3(0.24, 0.14, 0.29),
		Vector3(0.0, -0.68, 0.02), BOOTS))
	_left_leg.add_child(_box_node("SoleLeft", Vector3(0.25, 0.035, 0.31),
		Vector3(0.0, -0.755, 0.03), BOOT_SOLE))


func _pivot(node_name: String, at: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	node.position = at
	add_child(node)
	return node


func _box(node_name: String, box_size: Vector3, at: Vector3, colour: Color) -> MeshInstance3D:
	var instance := _box_node(node_name, box_size, at, colour)
	add_child(instance)
	return instance


func _box_node(node_name: String, box_size: Vector3, at: Vector3, colour: Color,
		shared_material: StandardMaterial3D = null) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = box_size
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = at
	instance.material_override = shared_material if shared_material != null else _material(colour)
	return instance


func _material(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.88
	material.metallic = 0.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return material


## Rebuilds the right-hand item from the authoritative selected item id.
func set_held_item(value: int, library: TextureLibrary) -> void:
	if value == _held_item and library == _held_library and _held_root.get_child_count() > 0:
		return
	if value == _held_item and library == _held_library and value == BlockDB.AIR:
		return
	_held_item = value
	_held_library = library
	for child in _held_root.get_children():
		child.free()
	if value == BlockDB.AIR or library == null:
		return
	var visual = HeldItemVisualScript.new()
	visual.name = "Item"
	var item_size: float = Presentation.item_size(value, true)
	visual.build(value, library, item_size)
	visual.position = Presentation.third_person_offset(value)
	_held_root.add_child(visual)
	var degrees: Vector3 = Presentation.third_person_rotation_degrees(value)
	_held_root.rotation_degrees = degrees


func visual_is_cube(value: int) -> bool:
	if not ItemDB.is_block(value) or value >= BlockDB.face_keys.size():
		return false
	return not (BlockDB.is_deco(value) or BlockDB.is_flower(value))


func held_item_id() -> int:
	return _held_item


func has_held_item() -> bool:
	return _held_root != null and _held_root.get_child_count() > 0


## Starts one arm swing.  Repeated calls restart it, which is what held-button
## mining wants: a visible, continuous chopping rhythm.
func play_swing() -> void:
	_swing_time = SWING_DURATION


## Advances walk/jump/swing animation.  `speed` is horizontal m/s.
func animate(delta: float, speed: float, on_floor: bool, vertical_velocity: float) -> void:
	_idle_time += delta
	var target_weight := clampf(speed / 5.4, 0.0, 1.0) if on_floor else 0.0
	_walk_weight = move_toward(_walk_weight, target_weight, delta * 5.0)
	if on_floor and speed > 0.05:
		_walk_phase += delta * maxf(speed, 1.0) * 2.15
	_swing_time = maxf(0.0, _swing_time - delta)
	var swing := 0.0
	if _swing_time > 0.0:
		var progress := 1.0 - _swing_time / SWING_DURATION
		swing = sin(progress * PI) * 1.15
	var stride := sin(_walk_phase) * 0.68 * _walk_weight
	if on_floor:
		_left_leg.rotation.x = stride
		_right_leg.rotation.x = -stride
		_left_arm.rotation.x = -stride * 0.85
		_right_arm.rotation.x = stride * 0.85 + swing * 0.85
		_left_arm.rotation.z = -ARM_OUT * 0.30
		_right_arm.rotation.z = ARM_OUT + swing * 0.55
	else:
		var fall := clampf(vertical_velocity / 12.0, -1.0, 1.0)
		_left_leg.rotation.x = -0.30 - fall * 0.15
		_right_leg.rotation.x = 0.34 + fall * 0.08
		_left_arm.rotation.x = -0.38
		_right_arm.rotation.x = -0.30 + swing * 0.85
		_left_arm.rotation.z = -ARM_OUT * 0.30
		_right_arm.rotation.z = ARM_OUT + swing * 0.55
	# A small breathing bob keeps an idle character from looking frozen.
	var breath := sin(_idle_time * 1.7) * 0.008
	position.y = breath
	# The right arm sways slightly outward when idle, like a hanging arm.
	if _walk_weight < 0.05 and _swing_time <= 0.0 and on_floor:
		_right_arm.rotation.z = ARM_OUT + sin(_idle_time * 1.3) * 0.015
		_left_arm.rotation.z = -ARM_OUT * 0.30 - sin(_idle_time * 1.3) * 0.015


## Height of the model above its feet; diagnostics and proportion checks.
func model_height() -> float:
	return 2.05


## Changes the right-hand skin material.  Kept for the preview's accent API.
func set_accent(colour: Color) -> void:
	if _hand_material != null:
		_hand_material.albedo_color = colour

class_name FirstPersonArms
extends Node3D

## The first-person hand and the item it holds.
##
## This is a camera-local model, not a world object.  The forearm enters from the
## lower-right edge of the frame at a shallow enough angle that the hand sits at a
## natural distance from the eye instead of filling the screen; the item is built
## at `ItemPresentation`'s first-person size and its grip is placed in the fist.
## Every part disables shadow casting, so the hands can never throw a false shadow
## into the world, and the whole assembly stays below the reticle.

const HeldItemVisualScript = preload("res://scripts/game/held_item_visual.gd")
const Presentation = preload("res://scripts/game/item_presentation.gd")

const SKIN := Color(0.68, 0.47, 0.32)
const SKIN_LIGHT := Color(0.78, 0.57, 0.40)
const SKIN_SHADOW := Color(0.52, 0.34, 0.22)
const SLEEVE := Color(0.72, 0.65, 0.50)
const SLEEVE_SHADE := Color(0.60, 0.53, 0.40)
const LEATHER := Color(0.31, 0.21, 0.13)
const LEATHER_LIGHT := Color(0.45, 0.31, 0.19)
const METAL := Color(0.55, 0.51, 0.43)

const SWING_DURATION := 0.28
## The shoulder pivot starts off-screen at the lower right.  Its forward pitch is
## just over 90 degrees, so the forearm travels *up* toward the hand instead of
## straight at the camera.  That single geometric choice is what stops the old
## pale sleeve slab from filling half the frame.
const RIGHT_BASE := Vector3(108.0, 8.0, -5.0)
const HAND_AT := Vector3(0.0, -0.45, 0.0)

var _right_arm: Node3D
var _hand_root: Node3D
var _held_root: Node3D
var _held_item := BlockDB.AIR
var _held_library: TextureLibrary
var _walk_phase := 0.0
var _walk_weight := 0.0
var _swing_time := 0.0
var _look_target := Vector2.ZERO
var _look_sway := Vector2.ZERO
var _materials: Dictionary = {}


func _init() -> void:
	_build()


func _build() -> void:
	_right_arm = Node3D.new()
	_right_arm.name = "RightArm"
	_right_arm.position = Vector3(0.46, -0.49, -0.28)
	_right_arm.rotation_degrees = RIGHT_BASE
	add_child(_right_arm)
	_add_arm_parts(_right_arm)

	# The fist is built in the held item's frame so the fingers can wrap across
	# the haft no matter which per-item orientation is selected.  Its basis is
	# updated with the item in `_apply_item_rotation`.
	_hand_root = Node3D.new()
	_hand_root.name = "GripHand"
	_hand_root.position = HAND_AT + Vector3(0.0, 0.0, -0.030)
	_right_arm.add_child(_hand_root)
	_build_hand(_hand_root)

	_held_root = Node3D.new()
	_held_root.name = "HeldItem"
	# The grip origin sits inside the closed palm.  The handle therefore passes
	# through the fist, with the curled fingers in front of it, instead of
	# floating beside the knuckles.
	_held_root.position = HAND_AT + Vector3(0.0, 0.0, -0.030)
	_right_arm.add_child(_held_root)
	_apply_item_rotation()


func _add_arm_parts(pivot: Node3D) -> void:
	# A cream tunic sleeve, a leather bracer and a bare hand.  Each section is a
	# separate, slightly different tone rather than one long pale box.
	var upper := _box("Sleeve", Vector3(0.108, 0.20, 0.104),
		Vector3(0.0, -0.10, 0.0), SLEEVE)
	pivot.add_child(upper)
	var lower := _box("SleeveLower", Vector3(0.094, 0.13, 0.092),
		Vector3(0.0, -0.245, 0.0), SLEEVE_SHADE)
	pivot.add_child(lower)
	var band := _box("SleeveBand", Vector3(0.100, 0.030, 0.098),
		Vector3(0.0, -0.310, 0.0), Color(0.66, 0.59, 0.44))
	pivot.add_child(band)
	var bracer := _box("Bracer", Vector3(0.086, 0.105, 0.084),
		Vector3(0.0, -0.373, 0.0), LEATHER)
	pivot.add_child(bracer)
	var bracer_trim := _box("BracerTrim", Vector3(0.090, 0.018, 0.088),
		Vector3(0.0, -0.424, 0.0), LEATHER_LIGHT)
	pivot.add_child(bracer_trim)
	var wrist := _box("Wrist", Vector3(0.066, 0.044, 0.066),
		Vector3(0.0, -0.426, 0.0), SKIN_SHADOW)
	pivot.add_child(wrist)
	# The wrist strap ties the sleeve and bracer to the bare hand.  The fist
	# itself is built in the held-item frame by `_build_hand`.
	var wrist_strap := _box("WristStrap", Vector3(0.070, 0.014, 0.070),
		Vector3(0.0, -0.410, 0.0), LEATHER_LIGHT)
	pivot.add_child(wrist_strap)


## The closed fist, modelled in the held item's local frame: +Y is the haft,
## +Z faces the camera.  The palm closes behind the haft, four finger wraps cross
## its front, and the thumb lies diagonally over them.  Because the whole hand
## shares the item's basis, the grip stays correct when a tool has its own lean.
func _build_hand(pivot: Node3D) -> void:
	var palm := _box("Palm", Vector3(0.074, 0.096, 0.050),
		Vector3(0.0, -0.006, -0.032), SKIN)
	pivot.add_child(palm)
	var heel := _box("PalmHeel", Vector3(0.072, 0.032, 0.058),
		Vector3(0.0, -0.062, -0.020), SKIN_SHADOW)
	pivot.add_child(heel)
	# Four horizontal finger wraps, stacked along the haft.  The narrow gaps
	# expose the darker palm and read as finger separation at gameplay distance.
	for index in 4:
		var finger_y := -0.036 + float(index) * 0.019
		var tone := SKIN_LIGHT if index % 2 == 0 else SKIN
		var wrap := _box("GripFinger%d" % index, Vector3(0.078, 0.015, 0.032),
			Vector3(0.0, finger_y, 0.030), tone)
		pivot.add_child(wrap)
		var knuckle_left := _box("GripFinger%dLeft" % index, Vector3(0.010, 0.017, 0.032),
			Vector3(-0.043, finger_y, 0.010), SKIN_SHADOW)
		pivot.add_child(knuckle_left)
		var knuckle_right := _box("GripFinger%dRight" % index, Vector3(0.010, 0.017, 0.032),
			Vector3(0.043, finger_y, 0.010), SKIN_SHADOW)
		pivot.add_child(knuckle_right)
	# Dark creases between the wraps keep the fingers readable when the hand is
	# lit from the front instead of merging into one pale block.
	for index in 3:
		var crease_y := -0.0265 + float(index) * 0.019
		var crease := _box("GripCrease%d" % index, Vector3(0.070, 0.004, 0.030),
			Vector3(0.0, crease_y, 0.031), SKIN_SHADOW)
		pivot.add_child(crease)
	# Thumb: three short segments crossing the front of the grip diagonally.
	var thumb_base := _box("GripThumbBase", Vector3(0.030, 0.040, 0.038),
		Vector3(-0.043, 0.022, 0.015), SKIN)
	thumb_base.rotation_degrees = Vector3(0.0, 0.0, 25.0)
	pivot.add_child(thumb_base)
	var thumb_bridge := _box("GripThumbBridge", Vector3(0.024, 0.055, 0.028),
		Vector3(-0.024, 0.006, 0.050), SKIN_LIGHT)
	thumb_bridge.rotation_degrees = Vector3(0.0, 0.0, 52.0)
	pivot.add_child(thumb_bridge)
	var thumb_tip := _box("GripThumbTip", Vector3(0.022, 0.032, 0.026),
		Vector3(-0.003, -0.014, 0.052), SKIN_SHADOW)
	thumb_tip.rotation_degrees = Vector3(0.0, 0.0, 68.0)
	pivot.add_child(thumb_tip)
	var wrist := _box("GripWrist", Vector3(0.062, 0.055, 0.060),
		Vector3(0.0, -0.090, -0.015), SKIN_SHADOW)
	pivot.add_child(wrist)
	var wrist_strap := _box("GripWristStrap", Vector3(0.066, 0.014, 0.062),
		Vector3(0.0, -0.101, -0.010), LEATHER_LIGHT)
	pivot.add_child(wrist_strap)


func _box(node_name: String, box_size: Vector3, at: Vector3, colour: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = box_size
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = at
	instance.material_override = _material(colour)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return instance


func _material(colour: Color) -> StandardMaterial3D:
	var key := colour.to_html(true)
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.94
	material.metallic = 0.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	# The arms are lit rather than flat-shaded: the old unshaded cream sleeve
	# bleached into a single bright slab under the outdoor sun.  A small amount
	# of emission keeps the hand readable in shadow without making it glow.
	material.emission_enabled = true
	material.emission = colour * 0.16
	_materials[key] = material
	return material


## Rebuilds the right-hand item.  The model owns no inventory state: the caller
## passes the authoritative selected id from `Inventory`.
func set_held_item(value: int, library: TextureLibrary) -> void:
	if value == _held_item and library == _held_library and _held_root.get_child_count() > 0:
		return
	if value == BlockDB.AIR and _held_root.get_child_count() == 0:
		return
	_held_item = value
	_held_library = library
	for child in _held_root.get_children():
		child.free()
	if value == BlockDB.AIR or library == null:
		# An empty hand returns to the neutral arm-space fist instead of keeping
		# the last tool's lean.
		_apply_item_rotation()
		return
	var visual = HeldItemVisualScript.new()
	visual.name = "Item"
	var item_size: float = Presentation.item_size(value, false)
	visual.build(value, library, item_size)
	visual.position = Presentation.first_person_offset(value)
	_held_root.add_child(visual)
	_apply_item_rotation()


## The item is a child of the arm so it follows the idle/walk/swing pose.  At
## rest its orientation is expressed in camera space: the arm's base rotation is
## removed once, then the item-specific pose is applied.  Animation keeps the
## same local basis, so the tool swings naturally with the hand.
func _apply_item_rotation() -> void:
	if _held_root == null:
		return
	var arm_basis := Basis.from_euler(Vector3(
		deg_to_rad(RIGHT_BASE.x), deg_to_rad(RIGHT_BASE.y), deg_to_rad(RIGHT_BASE.z)))
	var item_degrees: Vector3 = Presentation.first_person_rotation_degrees(_held_item)
	var item_basis := Basis.from_euler(Vector3(
		deg_to_rad(item_degrees.x), deg_to_rad(item_degrees.y), deg_to_rad(item_degrees.z)))
	var grip_basis := arm_basis.inverse() * item_basis
	_held_root.basis = grip_basis
	if _hand_root != null:
		# The hand shares the item's camera-space basis, so the finger wraps
		# always cross the haft at a right angle rather than following the arm.
		_hand_root.basis = grip_basis


func visual_is_cube(value: int) -> bool:
	if not ItemDB.is_block(value) or value >= BlockDB.face_keys.size():
		return false
	return not (BlockDB.is_deco(value) or BlockDB.is_flower(value))


func held_item_id() -> int:
	return _held_item


func has_held_item() -> bool:
	return _held_root != null and _held_root.get_child_count() > 0


## Mouse-look lag: the arms trail the camera very slightly instead of being
## rigidly welded to it.  This is deliberately much smaller than the old sway so
## the tool never becomes the subject of the shot.
func add_look_motion(relative: Vector2) -> void:
	_look_target.x = clampf(_look_target.x + relative.x * 0.00016, -0.026, 0.026)
	_look_target.y = clampf(_look_target.y + relative.y * 0.00016, -0.022, 0.022)


func play_swing() -> void:
	_swing_time = SWING_DURATION


## Advances walk bob, jump lift, look sway and the swing pose.
func animate(delta: float, speed: float, on_floor: bool, vertical_velocity: float) -> void:
	var target_weight := clampf(speed / 5.4, 0.0, 1.0) if on_floor else 0.0
	_walk_weight = move_toward(_walk_weight, target_weight, delta * 6.0)
	if on_floor and speed > 0.05:
		_walk_phase += delta * maxf(speed, 1.0) * 2.25
	_swing_time = maxf(0.0, _swing_time - delta)
	var swing := 0.0
	if _swing_time > 0.0:
		var progress := 1.0 - _swing_time / SWING_DURATION
		swing = sin(progress * PI)

	_look_sway = _look_sway.lerp(_look_target, minf(1.0, delta * 12.0))
	_look_target = _look_target.lerp(Vector2.ZERO, minf(1.0, delta * 7.0))
	rotation.y = _look_sway.x
	rotation.x = -_look_sway.y * 0.45

	var bob := sin(_walk_phase) * 0.0055 * _walk_weight
	var sway := cos(_walk_phase * 0.5) * 0.0035 * _walk_weight
	var jump_lift := clampf(vertical_velocity * 0.0018, -0.010, 0.010) if not on_floor else 0.0
	position = Vector3(sway, bob - jump_lift, 0.0)

	var stride := sin(_walk_phase) * 0.030 * _walk_weight
	_right_arm.rotation_degrees = RIGHT_BASE + Vector3(-swing * 7.0 + stride * 9.0,
		0.0, swing * 3.0 + cos(_walk_phase) * 0.9 * _walk_weight)

	if not on_floor:
		# Keep the hands readable while airborne: they dip slightly on the way up.
		var fall := clampf(vertical_velocity / 12.0, -1.0, 1.0)
		_right_arm.rotation_degrees += Vector3(-2.0 * fall, 0.0, 0.0)


## Combined camera-local AABB of every visible mesh in the hand assembly.
func local_bounds() -> AABB:
	var reference: Node3D = self
	var parent := get_parent()
	if parent is Node3D:
		reference = parent as Node3D
	var inverse := reference.global_transform.affine_inverse()
	var first := true
	var combined := AABB()
	for node: Node in find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh == null:
			continue
		var bounds := (inverse * mesh.global_transform) * mesh.get_aabb()
		if first:
			combined = bounds
			first = false
		else:
			combined = combined.merge(bounds)
	if first:
		return AABB(Vector3.ZERO, Vector3.ZERO)
	return combined


## Screen-space footprint of the hand and held item.  The visual acceptance
## contract uses this to prove the assembly stays in the lower-right quadrant
## rather than covering the centre of the view.
func screen_bounds(camera: Camera3D) -> Rect2:
	if camera == null:
		return Rect2()
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	var first := true
	for node: Node in find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh == null:
			continue
		var aabb := mesh.get_aabb()
		for corner in 8:
			var local := aabb.position + Vector3(
				aabb.size.x if corner & 1 else 0.0,
				aabb.size.y if corner & 2 else 0.0,
				aabb.size.z if corner & 4 else 0.0)
			var screen := camera.unproject_position(mesh.global_transform * local)
			minimum = minimum.min(screen)
			maximum = maximum.max(screen)
			first = false
	if first:
		return Rect2()
	return Rect2(minimum, maximum - minimum)


## True while no visible arm or item geometry overlaps the centre reticle.  The
## check uses the real MeshInstance AABBs in camera-local space (the arms are a
## child of the camera), so a future model change cannot silently break it.
func reticle_clear() -> bool:
	# The reticle sits at x=0, y=0; visible geometry must stay clearly below it.
	return reticle_top() < -0.05


## Highest point of any visible arm/item geometry in camera-local space.
func reticle_top() -> float:
	var bounds := local_bounds()
	if bounds.size == Vector3.ZERO:
		return -1.0
	return bounds.end.y

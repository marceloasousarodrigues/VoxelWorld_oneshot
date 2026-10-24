class_name VoxelPlayer
extends CharacterBody3D

const BlockShape = preload("res://scripts/core/block_shape.gd")
const PlayerCharacterScript = preload("res://scripts/game/player_character.gd")
const FirstPersonArmsScript = preload("res://scripts/game/first_person_arms.gd")

## Camera modes.  First person remains the default.
const CAMERA_FIRST := 0
const CAMERA_THIRD := 1

signal camera_mode_changed(mode: int)

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
## Emitted when the body touches down after being airborne, with the distance it
## fell.  The player never decides what that costs; the game layer applies the
## survival rule.
signal landed(fall_distance: float)
signal creature_attacked(creature: Node3D, damage: int)
## Emitted when the player uses the build action while holding food.  The game
## layer decides whether eating is worth it (a full body refuses) and consumes the
## item; the player never mutates the inventory itself.
signal eat_requested(item_id: int)
## Emitted when the player uses the build action holding wheat seeds over
## plantable soil.  The game layer tills and plants; the player never mutates the
## world or the inventory itself.
signal plant_requested(item_id: int, soil_cell: Vector3i)
## Emitted when the player uses the build action holding bone meal over a growing
## crop.  The game advances the crop and consumes one item.
signal fertilize_requested(item_id: int, crop_cell: Vector3i)
## Emitted when a block was broken but its drop needed a tool the player was not
## holding (`required_tool` is an `ItemDB.Tool` value).  The block still breaks;
## this is only the explanation for the missing drop.
signal harvest_failed(block_id: int, required_tool: int)
## Emitted when the held tool spent its last durability.
signal tool_broken(item_id: int)

const REACH := 6.0
const BODY_HEIGHT := 1.8
const BODY_RADIUS := 0.34
const EYE_HEIGHT := 1.62

## Camera shake: a bounded, decaying, *deterministic* oscillation (not a random
## one) so a capture with a shake still reproduces frame for frame.
const SHAKE_DURATION := 0.35
const SHAKE_MAX := 0.30
const SHAKE_FREQUENCY := 46.0

@export var move_speed := 5.4
@export var sprint_multiplier := 1.8
@export var jump_velocity := 8.9
@export var gravity := 24.0
@export var mouse_sensitivity := 0.0022
@export var fly_speed := 18.0
@export var repeat_interval := 0.2
@export var reach := REACH
@export var camera_distance := 3.8
## Over-the-shoulder offset: the camera sits to the player's right, so the body
## occupies the left third of the frame instead of hiding under the reticle.
## Targeting still converges on the crosshair, so this is framing only.
@export var camera_shoulder := 0.70
@export var camera_collision_radius := 0.22

var world: VoxelWorld
var inventory: Inventory
var texture_library: TextureLibrary
var camera: Camera3D
var third_person_camera: Camera3D
var first_person_arms
var character
var marker: MeshInstance3D

var camera_mode := CAMERA_FIRST

var flying := false
var can_interact := true
## When false the targeted-block outline is not drawn; the M18 visual test
## captures turn it off so the station geometry is unobstructed.
var show_target_marker := true
## Explicit facing for the next placed stair (0=+Z, 1=+X, 2=-Z, 3=-X), or -1 to
## derive it from the camera.  R cycles it so a roof row can be built while the
## camera looks along the wall instead of along the stair.
var placement_facing := -1

var _pitch := 0.0
var _break_cooldown := 0.0
var _place_cooldown := 0.0
var _hit: Dictionary = {"hit": false}
var _last_reported_key := ""
## Progressive mining: the cell being mined, and how far along it is (0..1).
## Holding the break action keeps accumulating; changing the target restarts.
var _mining_cell := Vector3i.ZERO
var _mining_ratio := 0.0
var _mining_active := false
## Fall tracking: the highest point of the current airborne arc, and whether the
## body is currently airborne.  A teleport resets both so a jump-cut never
## registers as a fall.
var _airborne := false
var _air_peak_y := 0.0
## Current camera-shake state.
var _shake_strength := 0.0
var _shake_time := 0.0
var _shake_phase := 0.0
var _shake_offset := Vector3.ZERO
## Third-person rig: the pivot inherits the player's yaw, the camera sits on the
## pivot's +Z (behind the character) and the distance is collision-clamped.
var _camera_pivot: Node3D
var _current_camera_distance := 0.0
## Collision-safe horizontal shoulder offset for the current frame.  A wall on
## the player's right collapses the shoulder before it collapses the whole arm.
var _current_camera_shoulder := 0.0
## Last selected hotbar item pushed into the visual models.
var _visual_item := -999
var _mining_swing_timer := 0.0


func _ready() -> void:
	_build_body()
	_build_camera()
	_build_visuals()
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


## Builds the visible player: a full articulated body for third person, camera
## arms for first person, and a collision-clamped third-person camera.  Nothing
## here owns gameplay state; all three follow the same controller.
func _build_visuals() -> void:
	first_person_arms = FirstPersonArmsScript.new()
	first_person_arms.name = "FirstPersonArms"
	camera.add_child(first_person_arms)
	first_person_arms.visible = camera_mode == CAMERA_FIRST

	character = PlayerCharacterScript.new()
	character.name = "Character"
	# The shared model faces +Z (the inventory preview looks at its face).  The
	# controller's forward is -Z, so the third-person body is turned to match.
	character.rotation.y = PI
	character.visible = camera_mode == CAMERA_THIRD
	add_child(character)

	_camera_pivot = Node3D.new()
	_camera_pivot.name = "ThirdPersonPivot"
	_camera_pivot.position.y = EYE_HEIGHT
	add_child(_camera_pivot)
	third_person_camera = Camera3D.new()
	third_person_camera.name = "ThirdPersonEye"
	third_person_camera.fov = camera.fov
	third_person_camera.near = camera.near
	third_person_camera.far = camera.far
	third_person_camera.rotation = Vector3.ZERO
	third_person_camera.position = Vector3(camera_shoulder, 0.0, camera_distance)
	third_person_camera.current = false
	_camera_pivot.add_child(third_person_camera)


## A target closer than this is not outlined.  When the camera is inside a block
## (spectator/fly captures, or standing in a leaf cell) the raycast reports a hit
## at distance zero and the 1 m outline surrounds the camera; its edges then read
## as thin dark vertical lines across the whole frame.  Hiding the outline for
## such near hits removes that artifact without changing normal block targeting.
const MIN_MARKER_DISTANCE := 0.75
## When collision forces the rear camera inside this radius, the body is hidden:
## a first-person-like view is preferable to a giant head filling the frame.  The
## character returns as soon as the camera has room again.
const CHARACTER_MIN_VISIBLE_DISTANCE := 1.35


static func target_marker_visible(hit: Dictionary, enabled: bool) -> bool:
	if not enabled or not bool(hit.get("hit", false)):
		return false
	return float(hit.get("distance", 0.0)) >= MIN_MARKER_DISTANCE


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

## Natural canopy and trunk blocks are not valid spawn ground: a dense M32 forest
## can put a leaf layer above the real surface, and scanning down from the top
## would otherwise start the player on top of a tree.
static func is_spawn_foliage(block_id: int) -> bool:
	return block_id == BlockDB.OAK_LEAVES or block_id == BlockDB.PINE_LEAVES \
		or block_id == BlockDB.BIRCH_LEAVES or block_id == BlockDB.BLOSSOM_LEAVES \
		or block_id == BlockDB.OAK_LOG or block_id == BlockDB.PINE_LOG \
		or block_id == BlockDB.BIRCH_LOG


## Topmost solid block in a column that is real ground or a player-built surface,
## skipping natural foliage and trunks.
static func spawn_ground_height(world: VoxelWorld, world_x: int, world_z: int, search_top: int = 110) -> int:
	var ground := search_top
	while ground > 1:
		var block := world.get_block(Vector3i(world_x, ground, world_z))
		if BlockDB.is_solid(block) and not is_spawn_foliage(block):
			return ground
		ground -= 1
	return maxi(1, ground)


## Places the player with its feet on top of the first solid block in a column.
func spawn_on_column(world_x: int, world_z: int, search_top: int = 110) -> void:
	var ground := spawn_ground_height(world, world_x, world_z, search_top)
	var spawn := Vector3(world_x + 0.5, float(ground) + 1.05, world_z + 0.5)
	teleport_to(spawn)


func teleport_to(world_position: Vector3) -> void:
	global_position = world_position
	velocity = Vector3.ZERO
	# A teleport is not a fall: restart the arc from wherever we now are.
	_airborne = false
	_air_peak_y = world_position.y


func look_yaw(degrees: float) -> void:
	rotation.y = deg_to_rad(degrees)


func look_pitch(degrees: float) -> void:
	_pitch = deg_to_rad(degrees)
	if camera != null:
		camera.rotation.x = _pitch


func eye_position() -> Vector3:
	if camera_mode == CAMERA_THIRD:
		return global_position + Vector3.UP * EYE_HEIGHT
	return camera.global_position if camera != null else global_position + Vector3.UP * EYE_HEIGHT


## Current yaw and pitch in degrees, for diagnostics and capture breadcrumbs.
func look_angles() -> Vector2:
	var pitch := camera.rotation.x if camera != null else _pitch
	return Vector2(rad_to_deg(rotation.y), rad_to_deg(pitch))


func look_basis() -> Basis:
	return Basis(Vector3.UP, rotation.y)


# --- camera modes --------------------------------------------------------

## Switches between the first-person arms view and the third-person body.  The
## controller, inventory, targeting and mouse capture are untouched; only which
## camera is current and which visual is visible changes.
func set_camera_mode(mode: int) -> void:
	var resolved := CAMERA_THIRD if mode == CAMERA_THIRD else CAMERA_FIRST
	camera_mode = resolved
	if first_person_arms != null:
		first_person_arms.visible = resolved == CAMERA_FIRST
	if character != null:
		character.visible = resolved == CAMERA_THIRD \
			and _current_camera_distance > CHARACTER_MIN_VISIBLE_DISTANCE
	if resolved == CAMERA_FIRST:
		_current_camera_distance = 0.0
		_current_camera_shoulder = 0.0
		if camera != null:
			camera.make_current()
	else:
		# Start close and ease out: a switch never snaps the camera through a
		# wall and never changes the player's world position.
		_current_camera_distance = minf(0.45, camera_distance)
		_current_camera_shoulder = 0.0
		if _camera_pivot != null:
			_camera_pivot.rotation.x = _pitch
		if third_person_camera != null:
			third_person_camera.make_current()
	if resolved == CAMERA_THIRD:
		_update_third_person_camera(0.0)
	camera_mode_changed.emit(camera_mode)


func toggle_camera_mode() -> void:
	set_camera_mode(CAMERA_THIRD if camera_mode == CAMERA_FIRST else CAMERA_FIRST)


func camera_mode_name() -> String:
	return "third_person" if camera_mode == CAMERA_THIRD else "first_person"


func set_camera_mode_name(name: String) -> void:
	set_camera_mode(CAMERA_THIRD if name == "third_person" else CAMERA_FIRST)


func is_third_person() -> bool:
	return camera_mode == CAMERA_THIRD


## Current collision-clamped camera distance, for diagnostics/tests.
func current_camera_distance() -> float:
	return _current_camera_distance


## Current collision-clamped shoulder offset, for diagnostics/tests.
func current_camera_shoulder() -> float:
	return _current_camera_shoulder


## The screen-centre look direction.  In third person this points from the eye
## toward the point the rear camera is looking at, preserving the same reach and
## the same crosshair target instead of aiming from behind the player's back.
func aim_direction() -> Vector3:
	if camera_mode == CAMERA_THIRD and third_person_camera != null:
		var focus := third_person_camera.global_position \
			- third_person_camera.global_basis.z * (_current_camera_distance + reach)
		var offset := focus - eye_position()
		if offset.length_squared() > 0.0001:
			return offset.normalized()
		return -third_person_camera.global_basis.z
	if camera != null:
		return -camera.global_basis.z
	return -global_basis.z


# --- frame loop ----------------------------------------------------------

func _process(delta: float) -> void:
	_break_cooldown = maxf(0.0, _break_cooldown - delta)
	_place_cooldown = maxf(0.0, _place_cooldown - delta)
	_update_shake(delta)
	_sync_camera_rig(delta)
	_update_target()
	_update_visuals(delta)
	if not can_interact or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_reset_mining()
		_mining_swing_timer = 0.0
		return
	if Input.is_action_pressed("break_block"):
		mine_step(delta)
		# Held-button mining plays a repeated chop, not one static arm.
		_mining_swing_timer = maxf(0.0, _mining_swing_timer - delta)
		if _mining_active and _mining_swing_timer <= 0.0:
			_mining_swing_timer = 0.24
			play_swing_animation()
	else:
		_reset_mining()
		_mining_swing_timer = 0.0
	if Input.is_action_pressed("place_block") and _place_cooldown <= 0.0:
		_place_cooldown = repeat_interval
		place_selected()


func _physics_process(delta: float) -> void:
	# `can_interact` is the game layer's "the world owns the input" flag.  It is
	# cleared while an inventory/crafting/settings/station overlay or the death
	# screen owns the mouse.  Movement must respect it too: polling WASD directly
	# here would otherwise walk the player behind an open interface even though
	# `_unhandled_input` correctly ignores discrete gameplay actions.
	var input := Vector2.ZERO
	var wants_sprint := false
	if can_interact:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
		wants_sprint = Input.is_action_pressed("sprint")
	var basis := look_basis()
	var direction := basis * Vector3(input.x, 0.0, input.y)
	if flying:
		var vertical := 0.0
		if can_interact and Input.is_action_pressed("jump"):
			vertical += 1.0
		if can_interact and Input.is_action_pressed("crouch"):
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
			if can_interact and Input.is_action_just_pressed("jump"):
				velocity.y = jump_velocity
			elif velocity.y < 0.0:
				velocity.y = -1.0
		else:
			velocity.y -= gravity * delta
	move_and_slide()
	_update_fall()


## Keeps the third-person pivot on the player's look pitch and moves the camera
## out behind the body, shortening it against world collision.  The first-person
## camera already carries its own pitch, so both views share one look state.
func _sync_camera_rig(delta: float) -> void:
	if _camera_pivot != null:
		_camera_pivot.rotation.x = _pitch
	if camera_mode != CAMERA_THIRD:
		return
	_update_third_person_camera(delta)


func _update_third_person_camera(delta: float) -> void:
	if _camera_pivot == null or third_person_camera == null:
		return
	var desired := maxf(0.45, camera_distance)
	# Collapse the shoulder before collapsing the arm.  A wall on the player's
	# right otherwise puts the camera's origin inside stone and reports a
	# near-zero distance even though the space behind the player is clear.
	var safe_shoulder := _camera_safe_shoulder(camera_shoulder)
	if safe_shoulder < _current_camera_shoulder or _current_camera_shoulder <= 0.0:
		_current_camera_shoulder = safe_shoulder
	else:
		_current_camera_shoulder = move_toward(_current_camera_shoulder, safe_shoulder, 2.2 * delta)
	_current_camera_shoulder = clampf(_current_camera_shoulder, 0.0, camera_shoulder)
	var safe := _camera_safe_distance(desired, _current_camera_shoulder)
	if safe < _current_camera_distance or _current_camera_distance <= 0.0:
		# Shortening is immediate: a camera must never pass through terrain.
		_current_camera_distance = safe
	else:
		_current_camera_distance = move_toward(_current_camera_distance, safe, 8.0 * delta)
	_current_camera_distance = clampf(_current_camera_distance, 0.0, desired)
	var ratio := (_current_camera_distance / desired) if desired > 0.0001 else 0.0
	third_person_camera.position = Vector3(_current_camera_shoulder * ratio + _shake_offset.x,
		_shake_offset.y, _current_camera_distance)
	third_person_camera.rotation = Vector3.ZERO
	if character != null:
		character.visible = _current_camera_distance > CHARACTER_MIN_VISIBLE_DISTANCE


## Distance the shoulder may move sideways without putting the camera origin
## inside a wall.  This is a short sphere sweep from the player's eye.
func _camera_safe_shoulder(desired: float) -> float:
	if desired <= 0.0001 or _camera_pivot == null or not is_inside_tree():
		return 0.0
	var space := get_world_3d().direct_space_state
	if space == null:
		return desired
	var sphere := SphereShape3D.new()
	sphere.radius = maxf(0.05, camera_collision_radius)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(_camera_pivot.global_basis, _camera_pivot.global_position)
	query.motion = _camera_pivot.global_basis * Vector3(desired, 0.0, 0.0)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	var result := space.cast_motion(query)
	if result.size() < 2:
		return desired
	return desired * clampf(result[0], 0.0, 1.0)


## Distance the rear camera can occupy without its collision sphere touching the
## voxel world.  The sweep starts at the camera's actual (collision-safe)
## shoulder-offset origin and travels straight back along the view axis, so the
## collision answer matches the position assigned in
## `_update_third_person_camera` exactly.  The player's own body is excluded;
## NPC/creature layers are not in the mask, so only terrain, walls and trees
## shorten the camera.
func _camera_safe_distance(desired: float, shoulder: float) -> float:
	if _camera_pivot == null or not is_inside_tree():
		return desired
	var space := get_world_3d().direct_space_state
	if space == null:
		return desired
	var sphere := SphereShape3D.new()
	sphere.radius = maxf(0.05, camera_collision_radius)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(_camera_pivot.global_basis,
		_camera_pivot.global_position + _camera_pivot.global_basis * Vector3(shoulder, 0.0, 0.0))
	query.motion = _camera_pivot.global_basis * Vector3(0.0, 0.0, desired)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	var result := space.cast_motion(query)
	if result.size() < 2:
		return desired
	return desired * clampf(result[0], 0.0, 1.0)


## Pushes the authoritative selected item and locomotion state into the visual
## models.  This is one-way presentation: the models never mutate the inventory.
func _update_visuals(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	if first_person_arms != null:
		first_person_arms.animate(delta, speed, is_on_floor(), velocity.y)
	if character != null:
		character.animate(delta, speed, is_on_floor(), velocity.y)
	if inventory != null:
		var item := inventory.selected_item()
		if item != _visual_item:
			_visual_item = item
			refresh_visuals()


## Re-reads the held item immediately (world start, tool break, scripted tests).
func refresh_visuals() -> void:
	if inventory == null:
		return
	var item := inventory.selected_item()
	_visual_item = item
	if first_person_arms != null:
		first_person_arms.set_held_item(item, texture_library)
	if character != null:
		character.set_held_item(item, texture_library)


func play_swing_animation() -> void:
	if first_person_arms != null:
		first_person_arms.play_swing()
	if character != null:
		character.play_swing()


## Tracks the peak of the current airborne arc and reports how far the body fell
## when it touches down.  Flying and teleporting are not falls.
func _update_fall() -> void:
	if flying:
		_airborne = false
		_air_peak_y = global_position.y
		return
	if is_on_floor():
		if _airborne:
			landed.emit(maxf(0.0, _air_peak_y - global_position.y))
			_airborne = false
		_air_peak_y = global_position.y
		return
	if not _airborne:
		_airborne = true
		_air_peak_y = global_position.y
	_air_peak_y = maxf(_air_peak_y, global_position.y)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= event.relative.x * mouse_sensitivity
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, deg_to_rad(-89.5), deg_to_rad(89.5))
		camera.rotation.x = _pitch
		if first_person_arms != null:
			first_person_arms.add_look_motion(event.relative)


func toggle_fly() -> void:
	flying = not flying
	velocity = Vector3.ZERO
	fly_changed.emit(flying)


# --- camera shake --------------------------------------------------------

## Adds a bounded, decaying camera shake.  Repeated calls take the strongest
## request instead of stacking, and the offset is always restored to zero.
func shake(strength: float, duration: float = SHAKE_DURATION) -> void:
	_shake_strength = clampf(maxf(_shake_strength, strength), 0.0, SHAKE_MAX)
	_shake_time = maxf(_shake_time, duration)


func _update_shake(delta: float) -> void:
	if _shake_time <= 0.0:
		if _shake_offset != Vector3.ZERO:
			_shake_offset = Vector3.ZERO
			_apply_shake()
		return
	_shake_time = maxf(0.0, _shake_time - delta)
	_shake_phase += delta * SHAKE_FREQUENCY
	var decay := clampf(_shake_time / SHAKE_DURATION, 0.0, 1.0)
	var strength := _shake_strength * decay
	_shake_offset = Vector3(sin(_shake_phase) * strength, cos(_shake_phase * 1.7) * strength, 0.0)
	_apply_shake()


func _apply_shake() -> void:
	if camera != null:
		camera.position = Vector3(_shake_offset.x, EYE_HEIGHT + _shake_offset.y, 0.0)


# --- targeting -----------------------------------------------------------

func _update_target() -> void:
	if world == null or camera == null:
		return
	var origin := eye_position()
	var found := VoxelRay.cast(world, origin, aim_direction(), reach)
	_hit = found
	if found.get("hit", false):
		var cell: Vector3i = found["block"]
		marker.global_position = Vector3(cell) + Vector3.ONE * 0.5
	marker.visible = target_marker_visible(found, show_target_marker)
	var key := "%s|%s" % [str(found.get("hit", false)), str(found.get("block", Vector3i.ZERO))]
	if key != _last_reported_key:
		_last_reported_key = key
		target_changed.emit(found)


func target() -> Dictionary:
	return _hit


# --- interaction ---------------------------------------------------------

## Held-button mining.  The block takes `ItemDB.break_seconds(block, held)` to
## break, so hardness and the held tool both matter; the progress bar in the HUD
## reads `mining_ratio()`.
func _update_mining(delta: float) -> void:
	var creature := _creature_in_front()
	if creature != null:
		# LMB keeps its creature-attack role; a creature in the crosshair wins
		# over the block behind it, exactly as the single-click path does.
		_reset_mining()
		if _break_cooldown <= 0.0:
			_break_cooldown = repeat_interval
			_attack(creature)
		return
	var hit := target()
	if not hit.get("hit", false):
		_reset_mining()
		return
	var cell: Vector3i = hit["block"]
	var block_id: int = hit["block_id"]
	if not BlockDB.is_breakable(block_id):
		_reset_mining()
		if _break_cooldown <= 0.0:
			_break_cooldown = repeat_interval * 3.0
			interaction_failed.emit("%s cannot be mined" % BlockDB.name_of(block_id))
		return
	var held := _held_item()
	if not ItemDB.harvestable(block_id, held):
		# A block that requires a tool cannot be removed at all without it.  Do
		# not accumulate progress and do not break the block for no reward: the
		# player gets an explanation and the world stays untouched.
		_reset_mining()
		if _break_cooldown <= 0.0:
			_break_cooldown = repeat_interval * 3.0
			harvest_failed.emit(block_id, ItemDB.required_tool(block_id))
		return
	if not _mining_active or cell != _mining_cell:
		_mining_cell = cell
		_mining_ratio = 0.0
		_mining_active = true
	var seconds := ItemDB.break_seconds(block_id, held)
	_mining_ratio = clampf(_mining_ratio + delta / seconds, 0.0, 1.0)
	if _mining_ratio >= 1.0:
		_mining_ratio = 0.0
		_mining_active = false
		_finish_break(cell, block_id)


## Mining progress of the current target, 0..1 (0 when not mining).
func mining_ratio() -> float:
	return _mining_ratio if _mining_active else 0.0


## One step of held-button mining.  `_process` calls this while the break action
## is held; tests and scripted captures call it directly, because a headless run
## cannot report a captured mouse.
func mine_step(delta: float) -> void:
	_update_mining(delta)


func _reset_mining() -> void:
	_mining_active = false
	_mining_ratio = 0.0


func _held_item() -> int:
	return inventory.selected_item() if inventory != null else BlockDB.AIR


## Instantly breaks the targeted block (tests, diagnostics and scripted
## captures).  Normal play goes through `_update_mining`, which honours hardness
## and the held tool.
func break_target() -> bool:
	var creature_hit := _creature_in_front()
	if creature_hit != null:
		_attack(creature_hit)
		return true
	var hit := target()
	if not hit.get("hit", false):
		interaction_failed.emit("No block in reach")
		return false
	var cell: Vector3i = hit["block"]
	var block_id: int = hit["block_id"]
	if not BlockDB.is_breakable(block_id):
		interaction_failed.emit("%s cannot be mined" % BlockDB.name_of(block_id))
		return false
	var held := _held_item()
	if not ItemDB.harvestable(block_id, held):
		harvest_failed.emit(block_id, ItemDB.required_tool(block_id))
		return false
	return _finish_break(cell, block_id)


## Removes the block, works out its drop (tool rules + deterministic bonus drops),
## spends tool durability and reports the outcome.  The tool requirement is
## rechecked here so no caller can remove a harvest-gated block for free.
func _finish_break(cell: Vector3i, block_id: int) -> bool:
	var held := _held_item()
	if not ItemDB.harvestable(block_id, held):
		harvest_failed.emit(block_id, ItemDB.required_tool(block_id))
		return false
	if not world.set_block(cell, BlockDB.AIR):
		interaction_failed.emit("That block is outside the loaded world")
		return false
	var drop := ItemDB.drop_for_block(block_id)
	if drop == BlockDB.NO_DROP:
		drop = ItemDB.bonus_drop(block_id, cell.x, cell.y, cell.z)
	_wear_held(held)
	block_broken.emit(cell, block_id, drop)
	play_swing_animation()
	_update_target()
	return true


## Applies one hit to a creature, scaled by the held item's attack damage, and
## spends tool durability.  Returns the damage dealt.
func _attack(creature: Node3D) -> int:
	var held := _held_item()
	var damage := maxi(1, int(round(ItemDB.attack_damage(held))))
	_wear_held(held)
	play_swing_animation()
	creature_attacked.emit(creature, damage)
	return damage


func _wear_held(held: int) -> void:
	if inventory == null or not ItemDB.is_tool_item(held):
		return
	var item_id := inventory.slots[inventory.selected]
	if inventory.wear(inventory.selected, 1):
		tool_broken.emit(item_id)


## Passive creature attacks share LMB with mining; the nearer physical target wins.
func _creature_in_front() -> Node3D:
	if camera == null:
		return null
	var origin := eye_position()
	var direction := aim_direction()
	var query := PhysicsRayQueryParameters3D.create(origin,
		origin + direction * reach, 2)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var body: Object = hit.get("collider")
	if body is Node3D and (body.is_in_group("passive_creature") or body.is_in_group("hostile_creature")
			or body.is_in_group("npc")):
		var block_distance := reach
		if _hit.get("hit", false):
			block_distance = float(_hit.get("distance", reach))
		if origin.distance_to(hit.position) < block_distance:
			return body as Node3D
	return null


func place_selected() -> bool:
	if inventory == null:
		return false
	var item_id := inventory.selected_item()
	if ItemDB.is_food(item_id):
		# Right-click eats when food is held; the game decides and consumes.  This
		# works while looking at the sky, so it does not need a target.
		play_swing_animation()
		eat_requested.emit(item_id)
		return true
	var hit := target()
	var aimed_block := int(hit.get("block_id", BlockDB.AIR)) if hit.get("hit", false) else BlockDB.AIR
	# Farming uses right-click on a world cell rather than placing a block, so it
	# is checked before the ordinary placement path.
	if item_id == ItemDB.WHEAT_SEEDS and hit.get("hit", false) \
			and Farming.PLANTABLE_SOIL.has(aimed_block):
		play_swing_animation()
		plant_requested.emit(item_id, hit["block"])
		return true
	if item_id == ItemDB.BONE_MEAL and hit.get("hit", false) and Farming.is_crop(aimed_block):
		play_swing_animation()
		fertilize_requested.emit(item_id, hit["block"])
		return true
	if not hit.get("hit", false):
		interaction_failed.emit("Nothing to build against")
		return false
	var preview := placement_preview()
	if preview.is_empty():
		if item_id == BlockDB.AIR:
			interaction_failed.emit("Hotbar slot is empty")
		else:
			interaction_failed.emit("%s is not a placeable block" % ItemDB.name_of(item_id))
		return false
	if not bool(preview["valid"]):
		interaction_failed.emit(str(preview.get("message", "That space is occupied")))
		return false
	var cell: Vector3i = preview["cell"]
	var block_id := int(preview["block"])
	var orientation := int(preview["orientation"])
	# `placement_preview` is the single authority for the destination, shape and
	# validity.  The action below consumes that exact result, so the ghost the
	# player sees cannot drift from what this call writes.
	if not world.set_block_state(cell, block_id, orientation):
		interaction_failed.emit("That block is outside the loaded world")
		return false
	block_placed.emit(cell, block_id)
	play_swing_animation()
	_update_target()
	return true


## Advances the explicit facing (R).  Returns the new facing, or -1 when the
## held item is not an orientable piece.  Stairs and slabs cycle the four
## facings (0..3); the ridge only has two meaningful axes (0 = X, 1 = Z).
func rotate_placement() -> int:
	if inventory == null:
		return -1
	var block_id := ItemDB.placeable_block(inventory.selected_item())
	if not BlockDB.is_orientable(block_id):
		return -1
	if block_id == BlockDB.SLATE_RIDGE:
		placement_facing = 0 if placement_facing < 0 else (placement_facing + 1) % 2
	else:
		placement_facing = 0 if placement_facing < 0 else (placement_facing + 1) % 4
	return placement_facing


## Orientation a shaped piece receives for a hit normal, honouring the explicit
## R rotation when it has been set and otherwise following the camera.  Stairs
## and slabs add four on a downward hit (upside-down); the ridge only rotates
## its long axis.
func placement_orientation(normal: Vector3i) -> int:
	var block_id := BlockDB.AIR
	if inventory != null:
		block_id = ItemDB.placeable_block(inventory.selected_item())
	if block_id == BlockDB.SLATE_RIDGE:
		if placement_facing < 0:
			return BlockShape.orientation_for_placement(aim_direction(), normal) % 2
		return placement_facing % 2
	if block_id == BlockDB.SLATE_RAMP:
		if placement_facing < 0:
			return BlockShape.orientation_for_placement(aim_direction(), normal) % 4
		return placement_facing % 4
	if placement_facing < 0:
		return BlockShape.orientation_for_placement(aim_direction(), normal)
	return placement_facing + (4 if normal == Vector3i.DOWN else 0)


## Human-readable state for the HUD/R-rotate prompt.
static func orientation_label(block_id: int, orientation: int) -> String:
	if block_id == BlockDB.SLATE_RIDGE:
		return "long axis %s" % ("X" if orientation % 2 == 0 else "Z")
	if BlockShape.is_slab(block_id):
		# The slab's only meaningful state is which half of the cell it fills.
		# The horizontal facing that R still cycles does not alter its geometry.
		return "top half (upside down)" if orientation >= 4 else "bottom half"
	return facing_name(orientation % 4) + (" upside down" if orientation >= 4 else "")


## Live build feedback used by the HUD: what the held block would do on the
## aimed face, and why it would be refused.  Returns {} when nothing placeable
## is selected.
func placement_preview() -> Dictionary:
	if inventory == null:
		return {}
	var item_id := inventory.selected_item()
	var block_id := ItemDB.placeable_block(item_id)
	if block_id == BlockDB.NO_DROP:
		return {}
	var hit := target()
	if not hit.get("hit", false):
		return {
			"item": item_id, "block": block_id, "hit": false, "valid": false,
			"reason": "aim at a block", "message": "Nothing to build against",
			"show": false,
		}
	var normal: Vector3i = hit["normal"]
	var target_cell: Vector3i = hit["block"]
	var cell: Vector3i = target_cell + normal
	var orientation := 0
	if BlockDB.is_orientable(block_id):
		orientation = placement_orientation(normal)
	var preview := {
		"item": item_id, "block": block_id, "hit": true,
		"target": target_cell, "cell": cell, "normal": normal,
		"orientation": orientation, "valid": true, "reason": "",
		"message": "", "show": true,
	}
	if not VoxelWorld.in_world_vertical(cell.y):
		preview["valid"] = false
		preview["reason"] = "outside the buildable height"
		preview["message"] = "Outside the buildable height"
		# There is no supported preview range outside the buildable height.
		preview["show"] = false
	elif world.get_block(cell) != BlockDB.AIR and not BlockDB.is_liquid(world.get_block(cell)):
		preview["valid"] = false
		preview["reason"] = "space occupied"
		preview["message"] = "That space is occupied"
	elif cell_intersects_body(cell, block_id, orientation):
		preview["valid"] = false
		preview["reason"] = "inside you"
		preview["message"] = "Cannot build inside yourself"
	elif not world.is_loaded(cell):
		preview["valid"] = false
		preview["reason"] = "outside the loaded world"
		preview["message"] = "That block is outside the loaded world"
		# A cell in a chunk that is not loaded cannot be inspected reliably.
		preview["show"] = false
	return preview


static func face_name(normal: Vector3i) -> String:
	match normal:
		Vector3i.UP:
			return "top"
		Vector3i.DOWN:
			return "underside"
		Vector3i.RIGHT:
			return "+X face"
		Vector3i.LEFT:
			return "-X face"
		Vector3i.BACK:
			return "+Z face"
		Vector3i.FORWARD:
			return "-Z face"
	return "face"


static func facing_name(facing: int) -> String:
	var names := ["+Z", "+X", "-Z", "-X"]
	if facing < 0 or facing >= names.size():
		return "?"
	return names[facing]


## True when the given world cell overlaps the player's collision volume.
func cell_intersects_body(cell: Vector3i, block_id: int = BlockDB.STONE, orientation: int = 0) -> bool:
	var feet := global_position
	var top := feet.y + BODY_HEIGHT
	for half_y in 2:
		for half_z in 2:
			for half_x in 2:
				var half_cell := Vector3i(half_x, half_y, half_z)
				if not BlockShape.is_occupied(block_id, orientation, half_cell):
					continue
				var minimum := Vector3(cell) + Vector3(half_cell) * 0.5
				var maximum := minimum + Vector3.ONE * 0.5
				if maximum.x > feet.x - BODY_RADIUS and minimum.x < feet.x + BODY_RADIUS \
						and maximum.y > feet.y + 0.05 and minimum.y < top \
						and maximum.z > feet.z - BODY_RADIUS and minimum.z < feet.z + BODY_RADIUS:
					return true
	return false


func is_submerged() -> bool:
	if world == null:
		return false
	return world.get_block(Vector3i(floori(eye_position().x), floori(eye_position().y), floori(eye_position().z))) == BlockDB.WATER

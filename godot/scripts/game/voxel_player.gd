class_name VoxelPlayer
extends CharacterBody3D

const BlockShape = preload("res://scripts/core/block_shape.gd")

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

var world: VoxelWorld
var inventory: Inventory
var camera: Camera3D
var marker: MeshInstance3D

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


## A target closer than this is not outlined.  When the camera is inside a block
## (spectator/fly captures, or standing in a leaf cell) the raycast reports a hit
## at distance zero and the 1 m outline surrounds the camera; its edges then read
## as thin dark vertical lines across the whole frame.  Hiding the outline for
## such near hits removes that artifact without changing normal block targeting.
const MIN_MARKER_DISTANCE := 0.75


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
	_update_shake(delta)
	_update_target()
	if not can_interact or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_reset_mining()
		return
	if Input.is_action_pressed("break_block"):
		mine_step(delta)
	else:
		_reset_mining()
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
	var found := VoxelRay.cast(world, camera.global_position, -camera.global_basis.z, reach)
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
	_update_target()
	return true


## Applies one hit to a creature, scaled by the held item's attack damage, and
## spends tool durability.  Returns the damage dealt.
func _attack(creature: Node3D) -> int:
	var held := _held_item()
	var damage := maxi(1, int(round(ItemDB.attack_damage(held))))
	_wear_held(held)
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
	var query := PhysicsRayQueryParameters3D.create(camera.global_position,
		camera.global_position - camera.global_basis.z * reach, 2)
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
		if camera.global_position.distance_to(hit.position) < block_distance:
			return body as Node3D
	return null


func place_selected() -> bool:
	if inventory == null:
		return false
	var item_id := inventory.selected_item()
	if ItemDB.is_food(item_id):
		# Right-click eats when food is held; the game decides and consumes.  This
		# works while looking at the sky, so it does not need a target.
		eat_requested.emit(item_id)
		return true
	var hit := target()
	var aimed_block := int(hit.get("block_id", BlockDB.AIR)) if hit.get("hit", false) else BlockDB.AIR
	# Farming uses right-click on a world cell rather than placing a block, so it
	# is checked before the ordinary placement path.
	if item_id == ItemDB.WHEAT_SEEDS and hit.get("hit", false) \
			and Farming.PLANTABLE_SOIL.has(aimed_block):
		plant_requested.emit(item_id, hit["block"])
		return true
	if item_id == ItemDB.BONE_MEAL and hit.get("hit", false) and Farming.is_crop(aimed_block):
		fertilize_requested.emit(item_id, hit["block"])
		return true
	if not hit.get("hit", false):
		interaction_failed.emit("Nothing to build against")
		return false
	var block_id := ItemDB.placeable_block(item_id)
	if block_id == BlockDB.NO_DROP:
		if item_id == BlockDB.AIR:
			interaction_failed.emit("Hotbar slot is empty")
		else:
			interaction_failed.emit("%s is not a placeable block" % ItemDB.name_of(item_id))
		return false
	var normal: Vector3i = hit["normal"]
	var cell: Vector3i = hit["block"] + normal
	if not VoxelWorld.in_world_vertical(cell.y):
		interaction_failed.emit("Outside the buildable height")
		return false
	var orientation := 0
	if BlockDB.is_orientable(block_id):
		orientation = placement_orientation(normal)
	var existing := world.get_block(cell)
	if existing != BlockDB.AIR and not BlockDB.is_liquid(existing):
		interaction_failed.emit("That space is occupied")
		return false
	if cell_intersects_body(cell, block_id, orientation):
		interaction_failed.emit("Cannot build inside yourself")
		return false
	if not world.set_block_state(cell, block_id, orientation):
		interaction_failed.emit("That block is outside the loaded world")
		return false
	block_placed.emit(cell, block_id)
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
			return BlockShape.orientation_for_placement(-camera.global_basis.z, normal) % 2
		return placement_facing % 2
	if block_id == BlockDB.SLATE_RAMP:
		if placement_facing < 0:
			return BlockShape.orientation_for_placement(-camera.global_basis.z, normal) % 4
		return placement_facing % 4
	if placement_facing < 0:
		return BlockShape.orientation_for_placement(-camera.global_basis.z, normal)
	return placement_facing + (4 if normal == Vector3i.DOWN else 0)


## Human-readable state for the HUD/R-rotate prompt.
static func orientation_label(block_id: int, orientation: int) -> String:
	if block_id == BlockDB.SLATE_RIDGE:
		return "long axis %s" % ("X" if orientation % 2 == 0 else "Z")
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
		return {"item": item_id, "block": block_id, "valid": false, "reason": "aim at a block"}
	var normal: Vector3i = hit["normal"]
	var cell: Vector3i = hit["block"] + normal
	var orientation := 0
	if BlockDB.is_orientable(block_id):
		orientation = placement_orientation(normal)
	var preview := {
		"item": item_id, "block": block_id, "cell": cell, "normal": normal,
		"orientation": orientation, "valid": true, "reason": "",
	}
	if not VoxelWorld.in_world_vertical(cell.y):
		preview["valid"] = false
		preview["reason"] = "outside the buildable height"
	elif world.get_block(cell) != BlockDB.AIR and not BlockDB.is_liquid(world.get_block(cell)):
		preview["valid"] = false
		preview["reason"] = "space occupied"
	elif cell_intersects_body(cell, block_id, orientation):
		preview["valid"] = false
		preview["reason"] = "inside you"
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

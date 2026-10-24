class_name CharacterPreview
extends SubViewportContainer

## A real rendered voxel character for the inventory's Player panel (M40).
##
## VoxelWorld has no exported player model, so the preview and the third-person
## camera share `PlayerCharacter`, a box-built voxel person in a transparent
## SubViewport.  It is a scene element, not a flattened texture: the camera, two
## lights and the parts are real 3D nodes, and the preview can be reused anywhere.
##
## It reflects only supported state: the same model proportions as the in-world
## body and the actually held hotbar item.  Equipment is *not* drawn because the
## game has no equipment system; the panel marks those slots as unavailable
## instead of inventing armour on the character.

const PlayerCharacterScript = preload("res://scripts/game/player_character.gd")

var _viewport: SubViewport
var _character


func _init() -> void:
	stretch = true
	custom_minimum_size = Vector2(150, 210)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Builds the preview.  Safe to call more than once; the scene is only created
## once.  Headless runs skip the 3D viewport (there is no render target to fill).
func setup() -> void:
	if _viewport != null or DisplayServer.get_name() == "headless":
		return
	_viewport = SubViewport.new()
	_viewport.name = "PreviewViewport"
	_viewport.transparent_bg = true
	# Only render while the inventory/character page is actually visible, so the
	# preview costs nothing during normal gameplay or on the crafting page.
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_viewport.msaa_3d = Viewport.MSAA_4X
	# `stretch = true` makes the container drive the render-target size.  Do not
	# mirror the control size back into the viewport from a `resized` handler: the
	# container's minimum size follows the viewport, so the two can feed layout
	# changes (for example a details-label height change) back into the preview.
	_viewport.size = Vector2i(200, 290)
	add_child(_viewport)
	_build_scene()


func is_rendering() -> bool:
	return _viewport != null


## The on-screen rectangle of the preview control (diagnostics/tests).
func preview_rect() -> Rect2:
	return Rect2(global_position, size)


## The render-target size, or (0, 0) in a headless run (diagnostics/tests).
func viewport_size() -> Vector2i:
	return _viewport.size if _viewport != null else Vector2i.ZERO


## Tints the right-hand skin material so the preview and the in-world character
## stay one model.  The inventory does not use this to fake equipment.
func set_accent(colour: Color) -> void:
	if _character != null:
		_character.set_accent(colour)


## Shows the item actually held in the hotbar on the preview character.  No
## inventory model is read here; the panel passes the authoritative item id.
func set_held_item(item_id: int, library: TextureLibrary) -> void:
	if _character != null:
		_character.set_held_item(item_id, library)


## Rotates the model (not the camera), so the preview framing never changes.
func rotate_by(degrees: float) -> void:
	if _character != null:
		_character.rotation.y = wrapf(_character.rotation.y + deg_to_rad(degrees), -PI, PI)


func reset_rotation() -> void:
	if _character != null:
		_character.rotation.y = deg_to_rad(17.0)


func _build_scene() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.74, 0.80, 0.92)
	environment.ambient_light_energy = 0.85
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	_viewport.add_child(world_environment)

	var camera := Camera3D.new()
	camera.fov = 30.0
	camera.position = Vector3(0.0, 1.26, 4.25)
	camera.look_at_from_position(Vector3(0.0, 1.26, 4.25), Vector3(0.0, 1.02, 0.0))
	_viewport.add_child(camera)

	var key := DirectionalLight3D.new()
	key.light_energy = 1.15
	key.light_color = Color(1.0, 0.96, 0.90)
	key.position = Vector3(1.6, 2.6, 2.4)
	key.look_at_from_position(Vector3(1.6, 2.6, 2.4), Vector3(0.0, 1.0, 0.0))
	_viewport.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.45
	fill.light_color = Color(0.72, 0.82, 1.0)
	fill.position = Vector3(-2.0, 1.4, 1.6)
	fill.look_at_from_position(Vector3(-2.0, 1.4, 1.6), Vector3(0.0, 1.0, 0.0))
	_viewport.add_child(fill)

	_character = PlayerCharacterScript.new()
	_character.name = "Character"
	_character.rotation.y = deg_to_rad(17.0)
	_viewport.add_child(_character)

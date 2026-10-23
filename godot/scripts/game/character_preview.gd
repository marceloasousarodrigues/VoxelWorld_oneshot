class_name CharacterPreview
extends SubViewportContainer

## A real rendered voxel character for the inventory's Player panel (M40).
##
## VoxelWorld is first person and has no exported player model, so this builds a
## small voxel person from boxes in a transparent SubViewport.  It is a scene
## element, not a flattened texture: the camera, two lights and the parts are real
## 3D nodes, and the preview can be reused anywhere.
##
## It reflects only supported state: the model itself and (optionally) a tint on
## the held-hand accent.  Equipment is *not* drawn because the game has no
## equipment system; the panel marks those slots as unavailable instead of
## inventing armour on the character.

const SKIN := Color(0.76, 0.56, 0.40)
const HAIR := Color(0.27, 0.17, 0.11)
const TUNIC := Color(0.80, 0.74, 0.60)
const BELT := Color(0.35, 0.24, 0.15)
const PANTS := Color(0.44, 0.34, 0.24)
const BOOTS := Color(0.24, 0.17, 0.12)
const EYE := Color(0.10, 0.08, 0.07)

var _viewport: SubViewport
var _character: Node3D
var _held_material: StandardMaterial3D


func _init() -> void:
	stretch = true
	custom_minimum_size = Vector2(150, 210)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_sync_viewport_size)


## Builds the preview.  Safe to call more than once; the scene is only created
## once.  Headless runs skip the 3D viewport (there is no render target to fill).
func setup() -> void:
	if _viewport != null or DisplayServer.get_name() == "headless":
		return
	_viewport = SubViewport.new()
	_viewport.name = "PreviewViewport"
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.size = Vector2i(300, 420)
	add_child(_viewport)
	_build_scene()
	_sync_viewport_size()


## Keeps the render target the same aspect as the on-screen panel.  With
## `stretch = true` a fixed 300x420 target would otherwise squash the character
## when the panel is tall and narrow.
func _sync_viewport_size() -> void:
	if _viewport == null:
		return
	_viewport.size = Vector2i(maxi(1, int(size.x)), maxi(1, int(size.y)))


func is_rendering() -> bool:
	return _viewport != null


## Tints a small accent part so a future held-item preview can hook in without
## rebuilding the model.  Today the panel only uses it for a subtle highlight.
func set_accent(colour: Color) -> void:
	if _held_material != null:
		_held_material.albedo_color = colour


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

	_character = Node3D.new()
	_character.name = "Character"
	_character.rotation.y = deg_to_rad(17.0)
	_viewport.add_child(_character)
	_build_character()


func _build_character() -> void:
	# Head and hair.
	_box("Head", Vector3(0.46, 0.46, 0.46), Vector3(0.0, 1.77, 0.0), SKIN)
	_box("HairTop", Vector3(0.50, 0.12, 0.50), Vector3(0.0, 1.99, 0.0), HAIR)
	_box("HairBack", Vector3(0.50, 0.46, 0.12), Vector3(0.0, 1.74, -0.21), HAIR)
	_box("HairLeft", Vector3(0.04, 0.22, 0.44), Vector3(-0.22, 1.88, 0.0), HAIR)
	_box("HairRight", Vector3(0.04, 0.22, 0.44), Vector3(0.22, 1.88, 0.0), HAIR)
	_box("HairFringe", Vector3(0.44, 0.08, 0.04), Vector3(0.0, 1.95, 0.235), HAIR)
	_box("EyeLeft", Vector3(0.08, 0.09, 0.03), Vector3(-0.10, 1.79, 0.240), EYE)
	_box("EyeRight", Vector3(0.08, 0.09, 0.03), Vector3(0.10, 1.79, 0.240), EYE)
	_box("Mouth", Vector3(0.12, 0.025, 0.02), Vector3(0.0, 1.69, 0.238), Color(0.55, 0.38, 0.32))
	_box("Neck", Vector3(0.18, 0.10, 0.18), Vector3(0.0, 1.49, 0.0), SKIN)

	# Torso, arms and hands.  The arms sit just outside the narrower tunic so
	# their silhouette is readable at preview size.
	_box("Tunic", Vector3(0.56, 0.66, 0.32), Vector3(0.0, 1.13, 0.0), TUNIC)
	_box("Collar", Vector3(0.32, 0.06, 0.34), Vector3(0.0, 1.44, 0.0), Color(0.70, 0.63, 0.50))
	_box("Belt", Vector3(0.58, 0.09, 0.34), Vector3(0.0, 0.84, 0.0), BELT)
	_box("Buckle", Vector3(0.10, 0.08, 0.03), Vector3(0.0, 0.84, 0.18), Color(0.78, 0.66, 0.36))
	_box("ArmLeft", Vector3(0.18, 0.60, 0.19), Vector3(-0.42, 1.15, 0.0), Color(0.76, 0.71, 0.60))
	_box("ArmRight", Vector3(0.18, 0.60, 0.19), Vector3(0.42, 1.15, 0.0), Color(0.76, 0.71, 0.60))
	_box("HandLeft", Vector3(0.18, 0.14, 0.20), Vector3(-0.42, 0.80, 0.0), SKIN)
	var right_hand := _box("HandRight", Vector3(0.18, 0.14, 0.20), Vector3(0.42, 0.80, 0.0), SKIN)
	_held_material = right_hand.material_override as StandardMaterial3D

	# Legs and boots.
	_box("LegLeft", Vector3(0.22, 0.62, 0.24), Vector3(-0.15, 0.45, 0.0), PANTS)
	_box("LegRight", Vector3(0.22, 0.62, 0.24), Vector3(0.15, 0.45, 0.0), PANTS)
	_box("BootLeft", Vector3(0.24, 0.14, 0.29), Vector3(-0.15, 0.10, 0.02), BOOTS)
	_box("BootRight", Vector3(0.24, 0.14, 0.29), Vector3(0.15, 0.10, 0.02), BOOTS)


func _box(node_name: String, box_size: Vector3, at: Vector3, colour: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = box_size
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.88
	material.metallic = 0.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	instance.material_override = material
	_character.add_child(instance)
	return instance

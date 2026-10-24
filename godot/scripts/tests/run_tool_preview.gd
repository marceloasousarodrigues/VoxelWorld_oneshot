extends SceneTree

## Supplementary model-inspection capture for M41c.  This is NOT gameplay
## evidence: it renders the held-item geometry on a neutral studio background so
## the silhouette, layering and materials can be inspected at a larger size.  The
## runtime capture script (`run_m41c_demo.gd`) remains the acceptance evidence.

const RESULTS := "res://../prototypes/m17/results/godot"
const Visual = preload("res://scripts/game/held_item_visual.gd")

var _root: Node3D
var _camera: Camera3D


func _initialize() -> void:
	call_deferred("_main")


func _main() -> void:
	_root = Node3D.new()
	root.add_child(_root)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.085, 0.09, 0.10)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.72, 0.76, 0.82)
	environment.ambient_light_energy = 0.70
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = environment
	_root.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, -28.0, 0.0)
	sun.light_energy = 1.35
	sun.light_color = Color(1.0, 0.95, 0.86)
	_root.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-16.0, 148.0, 0.0)
	fill.light_energy = 0.55
	fill.light_color = Color(0.76, 0.84, 1.0)
	_root.add_child(fill)

	_camera = Camera3D.new()
	_camera.fov = 34.0
	_camera.position = Vector3(0.0, 0.0, 5.0)
	_root.add_child(_camera)
	_camera.make_current()

	var library := TextureLibrary.new()
	library.load_all()
	var tools := [
		[ItemDB.WOOD_PICKAXE, -1.82],
		[ItemDB.STONE_AXE, -0.61],
		[ItemDB.IRON_SHOVEL, 0.61],
		[ItemDB.DIAMOND_SWORD, 1.82],
	]
	for entry: Array in tools:
		var visual = Visual.new()
		visual.name = "Tool%d" % int(entry[0])
		visual.build(int(entry[0]), library, 1.50)
		visual.position = Vector3(float(entry[1]), -0.60, 0.0)
		visual.rotation_degrees = Vector3(0.0, -18.0, 0.0)
		_root.add_child(visual)

	for index in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var directory := ProjectSettings.globalize_path(RESULTS)
	var path := directory.path_join("m41c-model-lineup.png")
	var error := root.get_texture().get_image().save_png(path)
	if error != OK:
		push_error("M41C_MODEL_PREVIEW_FAILED %s (%d)" % [path, error])
	print("M41C_MODEL_PREVIEW %s" % path)

	# A three-quarter view of the pickaxe alone makes the depth layering and the
	# grip/socket construction readable.
	for child in _root.get_children():
		if child is Node3D and child.name != "WorldEnvironment" and child != _camera \
				and not (child is DirectionalLight3D):
			child.queue_free()
	for index in 3:
		await process_frame
	var pick = Visual.new()
	pick.name = "Pickaxe"
	pick.build(ItemDB.WOOD_PICKAXE, library, 3.20)
	pick.position = Vector3(0.0, -1.52, 0.0)
	pick.rotation_degrees = Vector3(0.0, -38.0, 8.0)
	_root.add_child(pick)
	_camera.position = Vector3(0.0, 0.0, 5.0)
	_camera.fov = 34.0
	for index in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var path2 := directory.path_join("m41c-model-pickaxe.png")
	error = root.get_texture().get_image().save_png(path2)
	if error != OK:
		push_error("M41C_MODEL_PREVIEW_FAILED %s (%d)" % [path2, error])
	print("M41C_MODEL_PREVIEW %s" % path2)
	quit(0)

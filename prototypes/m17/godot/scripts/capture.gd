extends SceneTree

const MAIN_SCENE := preload("res://scenes/main.tscn")
const OUTPUT_DIR := "../results/godot"


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var scene := MAIN_SCENE.instantiate()
	scene.set("build_collisions", false)
	root.add_child(scene)
	await process_frame
	for frame_index: int in range(3):
		await process_frame
		RenderingServer.force_draw(false)
		await process_frame
	var capture_path := ProjectSettings.globalize_path("res://").path_join(OUTPUT_DIR).simplify_path()
	if not DirAccess.dir_exists_absolute(capture_path):
		DirAccess.make_dir_recursive_absolute(capture_path)
	var image := scene.get_viewport().get_texture().get_image()
	var screenshot_path := capture_path.path_join("godot-native-slice.png")
	var save_error := image.save_png(screenshot_path)
	if save_error != OK:
		push_error("Failed to save M17 screenshot (error %d)" % save_error)
		quit(1)
		return
	var file := FileAccess.open(capture_path.path_join("runtime-capture.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"evidence": "offscreen Godot rendered viewport PNG; this is not a screenshot of a desktop window or human visual inspection",
		"m17_status": "Native renderer prototype only; M17 six-criterion and autonomy evaluation not run",
		"fixture_sha256_checks": scene.fixture_metrics.get("hash_checks", 0),
		"fixture_expected_chunks": scene.fixture_metrics.get("count", 0),
		"shared_seed": scene.scenario.seed,
		"godot_version": Engine.get_version_info(),
		"resolution": [image.get_width(), image.get_height()],
		"sha256": FileAccess.get_sha256(screenshot_path),
		"loaded_fixture_chunks": scene.blocks.size(),
		"rendered_chunk_nodes": scene.chunk_nodes.size()
	}, "\t") + "\n")
	print("M17_CAPTURE_SAVED path=%s size=%dx%d chunks=%d" % [screenshot_path, image.get_width(), image.get_height(), scene.chunk_nodes.size()])
	quit(0)

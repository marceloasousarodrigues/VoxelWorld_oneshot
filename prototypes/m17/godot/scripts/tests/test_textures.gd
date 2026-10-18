extends RefCounted

## Texture library and material construction (headless-safe).


func name() -> String:
	return "textures and materials"


func run(h: TestHarness) -> void:
	var library := TextureLibrary.new()
	var loaded := library.load_all()
	h.check(loaded, "loads the vendored texture manifest and every PNG")
	if not loaded:
		h.finish()
		return
	h.check(library.array != null, "builds a Texture2DArray")
	h.eq(library.array.get_layers(), int(library.report["layers"]), "reports the layer count of the array")
	h.greater(float(library.tiles.size()), 20.0, "has more than twenty distinct tiles")
	h.greater(float(library.animated_frames("water_anim")), 1.0, "water animation has multiple frames")
	h.eq(library.animated_base("water_anim") + library.animated_frames("water_anim"), library.layer_index("water_anim") + library.animated_frames("water_anim"), "animated base resolves")

	# Every block face must resolve to a real layer.
	var unresolved := 0
	for block_id in BlockDB.COUNT:
		var keys: PackedStringArray = BlockDB.face_keys[block_id]
		for face in 6:
			var key := keys[face]
			if key.is_empty():
				continue
			if not library.layer_of.has(key):
				unresolved += 1
	h.eq(unresolved, 0, "every non-empty block face key resolves to a texture layer")

	var materials := VoxelMaterials.new(library)
	var missing := 0
	for layer in BlockDB.LAYER_COUNT:
		if materials.for_layer(layer) == null:
			missing += 1
	h.eq(missing, 0, "builds a material for every render layer")

	var mesher := ChunkMesher.new(library, materials)
	var missing_face_layers := 0
	for block_id in BlockDB.COUNT:
		for face in 6:
			if mesher.face_layer[block_id * 6 + face] < 0:
				missing_face_layers += 1
	h.eq(missing_face_layers, 0, "mesher resolves every block face to a layer index")

	var icon := library.icon("grass_top")
	h.check(icon != null, "exposes a HUD icon texture for a block face")
	h.eq(icon.get_width(), TextureLibrary.TILE_SIZE, "icon has the tile size")

	# Regression (M17 texture corruption): the array layer coordinate must be 
	# dispatched at exactly an integer. The first shaders sampled
	# `texture(atlas, vec3(UV, UV2.x + 0.5))`, which puts that coordinate exactly
	# on the midpoint between this layer and the next — this engine build rounds
	# the layer coordinate, so whole faces and per-pixel chunks of them rendered
	# the neighbouring array layer's texture (grass_top -> gravel, sand ->
	# sandstone, leaves -> log side), and per-pixel interpolation noise around
	# the midpoint flips individual fragments, so the patterns changed with the
	# camera. Runtime captures pinned the artifact; this contract test keeps the
	# + 0.5 offset out of the shaders.
	var shader_checks := [
		["res://shaders/voxel_opaque.gdshader", "vec3(UV, UV2.x)"],
		["res://shaders/voxel_cutout.gdshader", "vec3(UV, UV2.x)"],
		["res://shaders/voxel_blend.gdshader", "vec3(UV, UV2.x)"],
		["res://shaders/voxel_deco.gdshader", "vec3(UV, UV2.x)"],
		["res://shaders/voxel_water.gdshader", "vec3(UV, UV2.x + frame_a)"],
	]
	for shader_check: Array in shader_checks:
		var path: String = shader_check[0]
		var expected_sample: String = shader_check[1]
		var file := FileAccess.open(path, FileAccess.READ)
		var code := file.get_as_text() if file != null else ""
		h.check(not code.is_empty(), "reads %s for the layer-sampling contract" % path)
		if code.is_empty():
			continue
		var samples := code.split("texture(atlas, ")
		var sample_count := samples.size() - 1
		h.greater(float(sample_count), 0.0, "%s samples the atlas" % path)
		var midpoint_terms := 0
		for sample: String in samples.slice(1):
			# Only the expression up to the closing parenthesis matters.
			var expression := sample.split(")")[0]
			if "UV2.x" not in expression:
				continue
			midpoint_terms += 1
			h.eq(expression.count("+ 0.5") + expression.count("+0.5"), 0,
				"%s samples the layer coordinate exactly (no + 0.5 midpoint): %s" % [path, expression])
		h.greater(float(midpoint_terms), 0.0, "%s keeps sampling the UV2 layer coordinate" % path)

	h.finish()

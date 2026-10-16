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

	h.finish()

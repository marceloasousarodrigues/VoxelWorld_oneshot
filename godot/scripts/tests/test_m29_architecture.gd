extends RefCounted

## M29 medieval architectural palette: block ids, shaped pieces, custom models,
## roof helper, demos, recipes and player interaction.

const BlockShape = preload("res://scripts/core/block_shape.gd")
const BuildDemo = preload("res://scripts/game/build_demo.gd")
const StarterHouse = preload("res://scripts/game/starter_house.gd")
const FinalDemo = preload("res://scripts/game/final_demo.gd")

const PLASTER := 89
const DARK_TIMBER := 90
const STONE_WALL := 91
const TIMBER_BRACE := 92
const SLATE_TILE := 93
const SLATE_STAIR := 94
const SLATE_SLAB := 95
const SLATE_RIDGE := 96
const WINDOW := 97
const SHUTTER := 98
const CHIMNEY := 99
const FINIAL := 100
const FLOWER_BOX := 101
const RAMP := 102


func name() -> String:
	return "M29 medieval architecture"


func run(h: TestHarness) -> void:
	_block_palette(h)
	_block_shape(h)
	_mesher(h)
	_recipes(h)
	_interaction_and_save(h)
	_demos(h)
	h.finish()


func _block_palette(h: TestHarness) -> void:
	h.eq(PLASTER, BlockDB.PLASTER, "plaster appends after the M23 stair id")
	h.eq(DARK_TIMBER, BlockDB.DARK_TIMBER, "dark timber id follows plaster")
	h.eq(STONE_WALL, BlockDB.STONE_WALL, "stone wall id follows dark timber")
	h.eq(TIMBER_BRACE, BlockDB.TIMBER_BRACE, "timber brace id follows stone wall")
	h.eq(SLATE_TILE, BlockDB.SLATE_TILE, "slate tile id follows timber brace")
	h.eq(SLATE_STAIR, BlockDB.SLATE_STAIR, "slate stair id follows slate tile")
	h.eq(SLATE_SLAB, BlockDB.SLATE_SLAB, "slate slab id follows slate stair")
	h.eq(SLATE_RIDGE, BlockDB.SLATE_RIDGE, "slate ridge id follows slate slab")
	h.eq(WINDOW, BlockDB.WINDOW, "window id follows slate ridge")
	h.eq(SHUTTER, BlockDB.SHUTTER, "shutter id follows window")
	h.eq(CHIMNEY, BlockDB.CHIMNEY, "chimney id follows shutter")
	h.eq(FINIAL, BlockDB.FINIAL, "finial id follows chimney")
	h.eq(FLOWER_BOX, BlockDB.FLOWER_BOX, "flower box is the last appended M29 block")
	h.eq(RAMP, BlockDB.SLATE_RAMP, "the slate ramp appends after the M29 palette")
	h.eq(BlockDB.COUNT, 103, "the block table ends after the slate ramp")
	h.eq(BlockDB.DEFINED_COUNT, 71, "the slate ramp is fully defined")

	for block_id: int in [PLASTER, DARK_TIMBER, STONE_WALL, TIMBER_BRACE, SLATE_TILE,
			SLATE_STAIR, SLATE_SLAB, SLATE_RIDGE, WINDOW, SHUTTER, CHIMNEY, FINIAL, FLOWER_BOX,
			RAMP]:
		h.check(BlockDB.is_defined(block_id), "block %d is defined" % block_id)
		h.eq(BlockDB.drop_of(block_id), block_id, "block %d drops itself" % block_id)

	h.check(BlockDB.is_solid(PLASTER) and BlockDB.is_opaque(PLASTER), "plaster is a solid opaque cube")
	h.check(BlockDB.is_solid(DARK_TIMBER) and BlockDB.is_opaque(DARK_TIMBER), "dark timber is a solid opaque cube")
	h.check(BlockDB.is_solid(STONE_WALL) and BlockDB.is_opaque(STONE_WALL), "stone wall is a solid opaque cube")
	h.check(BlockDB.is_solid(TIMBER_BRACE) and BlockDB.is_opaque(TIMBER_BRACE), "timber brace is a solid opaque cube")
	h.check(BlockDB.is_solid(SLATE_TILE) and BlockDB.is_opaque(SLATE_TILE), "slate tile is a solid opaque cube")
	h.check(BlockDB.is_solid(SLATE_STAIR) and BlockDB.is_opaque(SLATE_STAIR), "slate stair is solid and opaque")
	h.check(BlockDB.is_solid(SLATE_SLAB) and BlockDB.is_opaque(SLATE_SLAB), "slate slab is solid and opaque")
	h.check(BlockDB.is_solid(SLATE_RIDGE) and BlockDB.is_custom_model(SLATE_RIDGE),
		"the slate ridge is a solid custom model")
	h.check(BlockDB.is_solid(WINDOW) and BlockDB.is_custom_model(WINDOW), "the window is a solid custom model")
	h.check(BlockDB.is_solid(SHUTTER) and not BlockDB.is_custom_model(SHUTTER), "the shutter is a plain louvered cube")
	h.check(BlockDB.is_solid(CHIMNEY) and BlockDB.is_custom_model(CHIMNEY), "the chimney is a solid custom model")
	h.check(not BlockDB.is_solid(FINIAL) and BlockDB.is_custom_model(FINIAL), "the finial is a non-solid custom model")
	h.check(not BlockDB.is_solid(FLOWER_BOX) and BlockDB.is_custom_model(FLOWER_BOX),
		"the flower box is a non-solid custom model")
	h.check(BlockDB.is_open_model(SLATE_RIDGE), "the triangular ridge does not cull neighbouring faces")
	h.check(BlockDB.is_open_model(WINDOW), "the window model does not cull neighbouring faces")
	h.check(BlockDB.is_open_model(CHIMNEY), "the chimney model does not cull neighbouring faces")
	h.check(BlockDB.is_solid(RAMP) and BlockDB.is_opaque(RAMP), "the slate ramp is solid and opaque")
	h.check(BlockDB.is_custom_model(RAMP), "the slate ramp is a custom wedge model")
	h.check(BlockDB.is_open_model(RAMP), "the wedge does not blanket-cull neighbouring faces")
	h.check(BlockShape.is_shaped(RAMP) == false, "the ramp is not the stepped half-cell shape path")

	h.eq(ItemDB.effective_tool(DARK_TIMBER), ItemDB.Tool.AXE, "dark timber is axe-mined")
	h.eq(ItemDB.effective_tool(TIMBER_BRACE), ItemDB.Tool.AXE, "timber brace is axe-mined")
	h.eq(ItemDB.effective_tool(SHUTTER), ItemDB.Tool.AXE, "shutters are axe-mined")
	h.eq(ItemDB.effective_tool(STONE_WALL), ItemDB.Tool.PICKAXE, "stone wall is pickaxe-mined")
	h.eq(ItemDB.required_tool(STONE_WALL), ItemDB.Tool.PICKAXE, "stone wall needs a pickaxe to drop")
	h.eq(ItemDB.effective_tool(SLATE_TILE), ItemDB.Tool.PICKAXE, "slate tile is pickaxe-mined")
	h.eq(ItemDB.effective_tool(SLATE_STAIR), ItemDB.Tool.PICKAXE, "slate stairs are pickaxe-mined")
	h.eq(ItemDB.required_tool(SLATE_SLAB), ItemDB.Tool.PICKAXE, "slate slabs need a pickaxe to drop")
	h.eq(ItemDB.required_tool(SLATE_RIDGE), ItemDB.Tool.PICKAXE, "slate ridges need a pickaxe to drop")
	h.eq(ItemDB.effective_tool(RAMP), ItemDB.Tool.PICKAXE, "slate ramps are pickaxe-mined")
	h.eq(ItemDB.required_tool(RAMP), ItemDB.Tool.PICKAXE, "slate ramps need a pickaxe to drop")
	h.eq(ItemDB.effective_tool(WINDOW), ItemDB.Tool.PICKAXE, "windows are pickaxe-mined")
	h.eq(ItemDB.required_tool(CHIMNEY), ItemDB.Tool.PICKAXE, "chimneys need a pickaxe to drop")
	h.eq(ItemDB.effective_tool(PLASTER), ItemDB.Tool.SHOVEL, "plaster is shovel-mined")
	h.eq(ItemDB.effective_tool(FLOWER_BOX), ItemDB.Tool.AXE, "the wooden flower box is axe-mined")

	for block_id: int in [PLASTER, DARK_TIMBER, STONE_WALL, TIMBER_BRACE, SLATE_TILE,
			SLATE_STAIR, SLATE_SLAB, SLATE_RIDGE, WINDOW, SHUTTER, CHIMNEY, FINIAL, FLOWER_BOX,
			RAMP]:
		h.check(ItemDB.is_valid(block_id), "block %d is a valid item" % block_id)
		h.check(ItemDB.is_block(block_id), "block %d is placeable" % block_id)
		h.check(ItemDB.placeable_block(block_id) == block_id, "block %d places itself" % block_id)

	h.check(BlockDB.is_orientable(BlockDB.STAIR), "the M23 stair stays orientable")
	h.check(BlockDB.is_orientable(SLATE_STAIR), "slate roof stairs are orientable")
	h.check(BlockDB.is_orientable(SLATE_SLAB), "slabs are orientable")
	h.check(BlockDB.is_orientable(SLATE_RIDGE), "ridges are orientable")
	h.check(BlockDB.is_orientable(RAMP), "slate ramps are orientable")
	h.eq(BlockDB.orientation_limit(RAMP), 3, "ramps use the four horizontal orientations only")
	h.eq(BlockDB.orientation_limit(SLATE_STAIR), 7, "stairs keep their upside-down orientations")
	h.eq(BlockDB.orientation_limit(SLATE_RIDGE), 7, "ridges keep the full orientation range")
	h.check(not BlockDB.is_orientable(PLASTER), "plaster is not orientable")
	h.check(not BlockDB.is_orientable(WINDOW), "the symmetric window is not orientable")


func _block_shape(h: TestHarness) -> void:
	h.check(BlockShape.is_shaped(SLATE_STAIR), "slate stairs use the shaped-block mesher")
	h.check(BlockShape.is_shaped(SLATE_SLAB), "slate slabs use the shaped-block mesher")
	h.check(not BlockShape.is_shaped(SLATE_RIDGE), "the ridge uses its custom prism model")
	h.check(BlockShape.is_shaped(BlockDB.STAIR), "the M23 stair stays shaped")
	h.check(not BlockShape.is_shaped(PLASTER), "full cubes are not shaped")

	h.eq(BlockShape.mask_for(SLATE_STAIR, 0), 0x3F, "slate stairs reuse the canonical stair mask")
	h.eq(BlockShape.mask_for(SLATE_STAIR, 6), BlockShape.mask_for(BlockDB.STAIR, 6),
		"slate stairs share every stair orientation")
	h.eq(_bit_count(BlockShape.mask_for(SLATE_SLAB, 0)), 4, "a bottom slab occupies the four lower cells")
	h.eq(BlockShape.mask_for(SLATE_SLAB, 0), 0x0F, "a bottom slab fills the lower half of the cell")
	h.eq(BlockShape.mask_for(SLATE_SLAB, 4), 0xF0, "an upside-down slab fills the upper half")
	h.eq(BlockShape.boundary_mask(SLATE_SLAB, 0, BlockDB.FACE_NY), 0xF,
		"a bottom slab covers its whole lower boundary")
	h.eq(BlockShape.boundary_mask(SLATE_SLAB, 0, BlockDB.FACE_PY), 0x0,
		"a bottom slab leaves its top boundary open")
	h.eq(BlockShape.boundary_mask(SLATE_SLAB, 4, BlockDB.FACE_PY), 0xF,
		"an upside-down slab covers its whole top boundary")
	h.eq(BlockShape.boundary_mask(SLATE_SLAB, 4, BlockDB.FACE_NY), 0x0,
		"an upside-down slab leaves its lower boundary open")
	h.eq(BlockShape.boundary_mask(SLATE_SLAB, 0, BlockDB.FACE_PZ), 0x3,
		"a slab covers half of each vertical boundary")
	h.eq(BlockShape.exposed_faces(SLATE_SLAB, 0).size(), 16,
		"a bottom slab has sixteen exposed half-cell faces")
	h.eq(BlockShape.exposed_faces(SLATE_STAIR, 0).size(), 22,
		"a slate stair has the same twenty-two exposed faces as the M23 stair")
	h.check(BlockShape.is_occupied(SLATE_SLAB, 0, Vector3i(1, 0, 1)),
		"the bottom slab is solid in its lower half")
	h.check(not BlockShape.is_occupied(SLATE_SLAB, 0, Vector3i(1, 0, 1) + Vector3i.UP),
		"the bottom slab is open above")
	h.check(BlockShape.is_occupied(SLATE_SLAB, 4, Vector3i(1, 1, 1)),
		"the upside-down slab is solid in its upper half")


func _bit_count(mask: int) -> int:
	var count := 0
	for bit in 8:
		if (mask & (1 << bit)) != 0:
			count += 1
	return count


func _mesher(h: TestHarness) -> void:
	var library := TextureLibrary.new()
	h.check(library.load_all(), "loads the M29 texture manifest")
	var materials := VoxelMaterials.new(library)
	var mesher := ChunkMesher.new(library, materials)

	# A bottom slab is four half-cells: sixteen exposed quads in both the render
	# and collision meshes.
	var slab_world := VoxelWorld.new(17017)
	var slab_chunk := _empty_chunk(slab_world)
	h.check(slab_world.set_block_state(Vector3i(8, 8, 8), SLATE_SLAB, 0),
		"a bottom slab can be written with orientation zero")
	var slab_result: Dictionary = mesher.build(slab_chunk, slab_world)
	h.eq(int(slab_result["faces"]), 16, "a bottom slab emits sixteen half-cell faces")
	var slab_collision: Array = slab_result["collision"].surface_get_arrays(0)
	h.eq((slab_collision[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), 64,
		"slab collision uses the same sixteen quads as rendering")
	var slab_arrays: Array = slab_result["mesh"].surface_get_arrays(0)
	var slab_vertices: PackedVector3Array = slab_arrays[Mesh.ARRAY_VERTEX]
	var slab_min_y := INF
	var slab_max_y := -INF
	for vertex: Vector3 in slab_vertices:
		slab_min_y = minf(slab_min_y, vertex.y)
		slab_max_y = maxf(slab_max_y, vertex.y)
	h.approx(slab_min_y, 8.0, 0.001, "the bottom slab starts at the cell floor")
	h.approx(slab_max_y, 8.5, 0.001, "the bottom slab stops at half height")

	# The upside-down slab occupies the top half of the same cell.
	slab_world.set_block_state(Vector3i(8, 8, 8), SLATE_SLAB, 4)
	var top_result: Dictionary = mesher.build(slab_chunk, slab_world)
	var top_arrays: Array = top_result["mesh"].surface_get_arrays(0)
	var top_vertices: PackedVector3Array = top_arrays[Mesh.ARRAY_VERTEX]
	var top_min_y := INF
	var top_max_y := -INF
	for vertex: Vector3 in top_vertices:
		top_min_y = minf(top_min_y, vertex.y)
		top_max_y = maxf(top_max_y, vertex.y)
	h.approx(top_min_y, 8.5, 0.001, "the upside-down slab starts at half height")
	h.approx(top_max_y, 9.0, 0.001, "the upside-down slab reaches the cell ceiling")

	# The slate roof stair keeps the M23 stair geometry and collision.
	var stair_world := VoxelWorld.new(17017)
	var stair_chunk := _empty_chunk(stair_world)
	h.check(stair_world.set_block_state(Vector3i(8, 8, 8), SLATE_STAIR, 0),
		"a slate stair can be written with orientation zero")
	var stair_result: Dictionary = mesher.build(stair_chunk, stair_world)
	h.eq(int(stair_result["faces"]), 22, "a slate stair emits twenty-two half-cell faces")
	h.eq((stair_result["collision"].surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(),
		88, "slate stair collision matches the M23 stair")

	# The slate ramp is a continuous one-cell wedge, not a half-cell stair.
	var ramp_world := VoxelWorld.new(17017)
	var ramp_chunk := _empty_chunk(ramp_world)
	h.check(ramp_world.set_block_state(Vector3i(8, 8, 8), RAMP, 0),
		"a slate ramp can be written with orientation zero")
	var ramp_result: Dictionary = mesher.build(ramp_chunk, ramp_world)
	h.eq(int(ramp_result["faces"]), 5,
		"an isolated ramp emits its bottom, back, slope and two end caps")
	h.eq((ramp_result["collision"].surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(),
		18, "ramp collision uses the same three quads and two triangle caps as rendering")
	var ramp_arrays: Array = ramp_result["mesh"].surface_get_arrays(0)
	var ramp_normals: PackedVector3Array = ramp_arrays[Mesh.ARRAY_NORMAL]
	var ramp_uv2: PackedVector2Array = ramp_arrays[Mesh.ARRAY_TEX_UV2]
	var slope_normal := Vector3.ZERO
	var saw_tile_layer := false
	var saw_side_layer := false
	for index in ramp_normals.size():
		if ramp_normals[index].y > 0.5:
			slope_normal = ramp_normals[index]
		if int(ramp_uv2[index].x) == library.layer_index("slate_tile"):
			saw_tile_layer = true
		elif int(ramp_uv2[index].x) == library.layer_index("slate_side"):
			saw_side_layer = true
	h.check(slope_normal.y > 0.5 and slope_normal.z > 0.1,
		"orientation zero slopes down toward +Z")
	h.check(saw_tile_layer, "the ramp top plane samples the slate tile texture")
	h.check(saw_side_layer, "the ramp edge/back samples the slate side texture")
	h.eq(_bad_winding(ramp_arrays), 0, "all ramp triangles wind like Godot's front faces")
	var ramp_collision_arrays: Array = ramp_result["collision"].surface_get_arrays(0)
	var collision_vertices: PackedVector3Array = ramp_collision_arrays[Mesh.ARRAY_VERTEX]
	var collision_indices: PackedInt32Array = ramp_collision_arrays[Mesh.ARRAY_INDEX]
	var inward_slope := false
	var i := 0
	while i + 2 < collision_indices.size():
		var a := collision_vertices[int(collision_indices[i])]
		var b := collision_vertices[int(collision_indices[i + 1])]
		var c := collision_vertices[int(collision_indices[i + 2])]
		var geometric := (b - a).cross(c - a).normalized()
		if geometric.y < -0.3 and geometric.z < -0.3:
			inward_slope = true
		i += 3
	h.check(inward_slope, "the collision slope is wound inward like the render mesh")

	ramp_world.set_block_state(Vector3i(8, 8, 8), RAMP, 1)
	var rotated_ramp: Dictionary = mesher.build(ramp_chunk, ramp_world)
	var ramp_rotated_normals: PackedVector3Array = rotated_ramp["mesh"].surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	var rotated_slope := Vector3.ZERO
	for normal: Vector3 in ramp_rotated_normals:
		if normal.y > 0.5:
			rotated_slope = normal
	h.check(rotated_slope.x > 0.1, "orientation one slopes down toward +X")

	# A ramp sitting on a solid cube omits its bottom face, so it cannot z-fight
	# with the support's top face.
	var ramp_base_world := VoxelWorld.new(17017)
	var ramp_base_chunk := _empty_chunk(ramp_base_world)
	ramp_base_world.set_block(Vector3i(8, 8, 8), BlockDB.STONE)
	ramp_base_world.set_block_state(Vector3i(8, 9, 8), RAMP, 0)
	var ramp_base_result: Dictionary = mesher.build(ramp_base_chunk, ramp_base_world)
	h.eq((ramp_base_result["collision"].surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(),
		38, "the supported ramp loses its floor face while the cube keeps its top")
	h.eq(int(ramp_base_result["faces"]), 6 + 4,
		"the supported ramp renders four faces and the cube keeps all six")

	# Adjacent ramps in a row share their end caps instead of z-fighting.
	var ramp_row_world := VoxelWorld.new(17017)
	var ramp_row_chunk := _empty_chunk(ramp_row_world)
	ramp_row_world.set_block_state(Vector3i(8, 8, 8), RAMP, 0)
	ramp_row_world.set_block_state(Vector3i(9, 8, 8), RAMP, 0)
	var ramp_row_result: Dictionary = mesher.build(ramp_row_chunk, ramp_row_world)
	h.eq(int(ramp_row_result["faces"]), 8,
		"two adjacent ramps cull their shared end caps")
	h.eq((ramp_row_result["collision"].surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(),
		30, "the adjacent-ramp collision matches the culled render faces")

	# Neighbour culling follows the shaped coverage: a bottom slab directly above
	# a cube hides that cube's top face, while a top slab leaves it visible.
	var cull_world := VoxelWorld.new(17017)
	var cull_chunk := _empty_chunk(cull_world)
	cull_world.set_block(Vector3i(8, 8, 8), BlockDB.STONE)
	cull_world.set_block_state(Vector3i(8, 9, 8), SLATE_SLAB, 0)
	var cull_result: Dictionary = mesher.build(cull_chunk, cull_world)
	h.eq((cull_result["collision"].surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(),
		17 * 4, "the covered cube face and the slab's lower boundary are culled")
	cull_world.set_block_state(Vector3i(8, 9, 8), SLATE_SLAB, 4)
	var open_result: Dictionary = mesher.build(cull_chunk, cull_world)
	h.eq((open_result["collision"].surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(),
		25 * 4, "a top slab leaves the cube top face visible as four patches")

	# The ridge is a custom triangular prism: geometry, UV layer, collision and
	# orientation-dependent slope normals.
	var ridge_world := VoxelWorld.new(17017)
	var ridge_chunk := _empty_chunk(ridge_world)
	h.check(ridge_world.set_block_state(Vector3i(8, 8, 8), SLATE_RIDGE, 0),
		"a ridge can be written with orientation zero")
	var ridge_result: Dictionary = mesher.build(ridge_chunk, ridge_world)
	h.check(ridge_result["mesh"] != null, "the ridge emits render geometry")
	h.check(ridge_result["collision"] != null, "the ridge keeps full-cell collision")
	h.eq((ridge_result["collision"].surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(),
		24, "ridge collision is one full cube")
	var ridge_arrays: Array = ridge_result["mesh"].surface_get_arrays(0)
	var ridge_vertices: PackedVector3Array = ridge_arrays[Mesh.ARRAY_VERTEX]
	var ridge_normals: PackedVector3Array = ridge_arrays[Mesh.ARRAY_NORMAL]
	var ridge_uv2: PackedVector2Array = ridge_arrays[Mesh.ARRAY_TEX_UV2]
	var ridge_layer := library.layer_index("slate_ridge")
	var ridge_layer_faces := 0
	for index in ridge_uv2.size():
		if int(ridge_uv2[index].x) == ridge_layer:
			ridge_layer_faces += 1
	h.greater(float(ridge_layer_faces), 0.0, "ridge faces carry the slate ridge texture layer")
	h.eq(ridge_normals.size(), ridge_vertices.size(), "ridge normals match its vertices")
	var sloped_z := 0
	for normal: Vector3 in ridge_normals:
		if normal.y > 0.1 and absf(normal.z) > 0.1:
			sloped_z += 1
	h.greater(float(sloped_z), 0.0, "an X-axis ridge slopes toward +/-Z")
	h.eq(_bad_winding(ridge_arrays), 0, "all ridge triangles wind like Godot's front faces")
	h.eq(_bad_collision_winding(ridge_result["collision"], Vector3(8.5, 8.5, 8.5)), 0,
		"ridge collision winds toward the cell interior")

	ridge_world.set_block_state(Vector3i(8, 8, 8), SLATE_RIDGE, 1)
	var rotated_ridge: Dictionary = mesher.build(ridge_chunk, ridge_world)
	var rotated_arrays: Array = rotated_ridge["mesh"].surface_get_arrays(0)
	var rotated_normals: PackedVector3Array = rotated_arrays[Mesh.ARRAY_NORMAL]
	var sloped_x := 0
	for normal: Vector3 in rotated_normals:
		if normal.y > 0.1 and absf(normal.x) > 0.1:
			sloped_x += 1
	h.greater(float(sloped_x), 0.0, "a rotated ridge slopes toward +/-X")

	# Window, chimney, finial and flower box are chunk-mesh models too.
	var detail_world := VoxelWorld.new(17017)
	var detail_chunk := _empty_chunk(detail_world)
	detail_world.set_block_state(Vector3i(4, 8, 4), WINDOW, 0)
	detail_world.set_block_state(Vector3i(8, 8, 8), CHIMNEY, 0)
	detail_world.set_block_state(Vector3i(12, 8, 12), FINIAL, 0)
	detail_world.set_block_state(Vector3i(4, 8, 12), FLOWER_BOX, 0)
	var detail_result: Dictionary = mesher.build(detail_chunk, detail_world)
	h.greater(float(detail_result["faces"]), 30.0, "the facade details emit real geometry")
	h.check(detail_result["collision"] != null, "the solid details keep collision")
	h.eq((detail_result["collision"].surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(),
		48, "window and chimney keep full-cube collision; the finial and planter do not")
	var detail_uv2: PackedVector2Array = _all_uv2(detail_result["mesh"])
	var saw_window := false
	var saw_chimney := false
	var saw_finial := false
	var saw_flower := false
	for uv: Vector2 in detail_uv2:
		if int(uv.x) == library.layer_index("window"):
			saw_window = true
		elif int(uv.x) == library.layer_index("chimney_side"):
			saw_chimney = true
		elif int(uv.x) == library.layer_index("finial"):
			saw_finial = true
		elif int(uv.x) == library.layer_index("flower_box"):
			saw_flower = true
	h.check(saw_window, "the window model samples its window texture")
	h.check(saw_chimney, "the chimney model samples its masonry texture")
	h.check(saw_finial, "the finial model samples its iron texture")
	h.check(saw_flower, "the flower box samples its planter texture")

	# The finial cell sits one block above the ridge; its post must reach down to
	# the ridge cap apex (finial cell bottom - 0.5), or it renders as a floating
	# spike.  This is the geometry assertion that would fail with the old -0.5
	# post start.
	var finial_world := VoxelWorld.new(17017)
	var finial_chunk := _empty_chunk(finial_world)
	h.check(finial_world.set_block_state(Vector3i(8, 9, 8), FINIAL, 0),
		"a finial can be written above a ridge cell")
	var finial_result: Dictionary = mesher.build(finial_chunk, finial_world)
	var finial_arrays: Array = finial_result["mesh"].surface_get_arrays(0)
	var finial_vertices: PackedVector3Array = finial_arrays[Mesh.ARRAY_VERTEX]
	var finial_min_y := INF
	for vertex: Vector3 in finial_vertices:
		finial_min_y = minf(finial_min_y, vertex.y)
	h.approx(finial_min_y, 8.5, 0.001,
		"the finial post reaches the ridge apex half a block below its cell")
	h.check(finial_min_y <= 8.5 + 0.001,
		"the finial geometry physically meets/overlaps the ridge apex")

	# Open custom models must not hide the face of the block they sit on.
	var open_world := VoxelWorld.new(17017)
	var open_chunk := _empty_chunk(open_world)
	open_world.set_block(Vector3i(8, 8, 8), BlockDB.STONE)
	open_world.set_block_state(Vector3i(8, 9, 8), WINDOW, 0)
	var open_result2: Dictionary = mesher.build(open_chunk, open_world)
	h.eq((open_result2["collision"].surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(),
		11 * 4, "the window leaves the cube top visible while its own base is culled")


func _empty_chunk(world: VoxelWorld) -> ChunkData:
	var chunk := ChunkData.new(Vector3i.ZERO)
	chunk.generated = true
	world.adopt_chunk(chunk)
	return chunk


func _recipes(h: TestHarness) -> void:
	var expected := {
		"plaster": PLASTER,
		"dark_timber": DARK_TIMBER,
		"stone_wall": STONE_WALL,
		"timber_brace": TIMBER_BRACE,
		"slate_tile": SLATE_TILE,
		"slate_roof_stair": SLATE_STAIR,
		"slate_slab": SLATE_SLAB,
		"slate_ramp": RAMP,
		"slate_ridge": SLATE_RIDGE,
		"window": WINDOW,
		"shutter": SHUTTER,
		"chimney": CHIMNEY,
		"finial": FINIAL,
		"flower_box": FLOWER_BOX,
	}
	for recipe_id: String in expected:
		var recipe: Dictionary = Crafting.recipe(recipe_id)
		h.check(not recipe.is_empty(), "recipe %s exists" % recipe_id)
		if recipe.is_empty():
			continue
		h.eq(Crafting.validate(recipe), "", "recipe %s validates" % recipe_id)
		h.eq(int(recipe["output"]), int(expected[recipe_id]), "recipe %s outputs its block" % recipe_id)
		h.eq(Crafting.station_of(recipe), Crafting.STATION_TABLE,
			"recipe %s is a crafting-table recipe" % recipe_id)
		var inventory := Inventory.new()
		for item_id in Crafting.ingredients(recipe):
			inventory.add(int(item_id), int(Crafting.ingredients(recipe)[item_id]))
		var result: Dictionary = Crafting.craft(inventory, recipe, Crafting.STATION_TABLE)
		h.check(bool(result["ok"]), "recipe %s crafts at the table" % recipe_id)
		h.eq(inventory.count_of(int(expected[recipe_id])), int(recipe["output_count"]),
			"recipe %s yields its output count" % recipe_id)

	# The roof palette is reachable in one chain from stone and clay.
	var chain := Inventory.new()
	chain.add(BlockDB.STONE, 16)
	chain.add(BlockDB.CLAY, 8)
	chain.add(BlockDB.PLANKS, 8)
	chain.add(BlockDB.COBBLESTONE, 8)
	chain.add(ItemDB.STICK, 4)
	chain.add(ItemDB.COAL, 4)
	chain.add(BlockDB.SAND, 4)
	chain.add(BlockDB.GLASS, 4)
	chain.add(BlockDB.BRICK, 2)
	chain.add(ItemDB.IRON_INGOT, 2)
	chain.add(BlockDB.DIRT, 2)
	for recipe_id: String in ["slate_tile", "slate_tile", "slate_tile", "plaster", "dark_timber",
			"dark_timber", "stone_wall", "timber_brace", "slate_roof_stair", "slate_ramp",
			"slate_slab", "slate_ridge", "window", "shutter", "chimney", "finial", "flower_box"]:
		var step: Dictionary = Crafting.craft(chain, Crafting.recipe(recipe_id), Crafting.STATION_TABLE)
		h.check(bool(step["ok"]), "the %s chain step succeeds (%s)" % [recipe_id, str(step["reason"])])
	h.check(chain.count_of(SLATE_STAIR) > 0, "the chain produces slate roof stairs")
	h.check(chain.count_of(RAMP) > 0, "the chain produces slate roof ramps")
	h.check(chain.count_of(SLATE_RIDGE) > 0, "the chain produces slate ridges")
	h.check(chain.count_of(WINDOW) > 0, "the chain produces framed windows")
	h.check(chain.count_of(CHIMNEY) > 0, "the chain produces chimneys")


func _interaction_and_save(h: TestHarness) -> void:
	# Placement state is not stair-only any more: the slab and ridge expose the
	# same rotate/placement surface, and an ordinary full cube still refuses.
	var world := VoxelWorld.new(17017)
	var chunk := ChunkData.new(Vector3i.ZERO)
	chunk.generated = true
	world.adopt_chunk(chunk)
	world.set_block(Vector3i(8, 8, 8), BlockDB.STONE)
	world.set_block(Vector3i(10, 8, 8), BlockDB.STONE)
	world.set_block(Vector3i(12, 8, 8), BlockDB.STONE)
	world.set_block(Vector3i(14, 8, 8), BlockDB.STONE)
	var player := VoxelPlayer.new()
	player.world = world
	player.inventory = Inventory.new()
	player.set_process(false)
	player.set_physics_process(false)
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(player)
	player.teleport_to(Vector3(100.0, 100.0, 100.0))
	player.look_yaw(-90.0)

	player.inventory.add(SLATE_RIDGE, 2)
	h.check(_select(player.inventory, SLATE_RIDGE), "the slate ridge is selectable")
	player.placement_facing = -1
	h.eq(player.rotate_placement(), 0, "R starts the ridge on its X axis")
	h.eq(player.rotate_placement(), 1, "R turns the ridge onto its Z axis")
	h.eq(player.rotate_placement(), 0, "R cycles the ridge axis back to X")
	player.placement_facing = 1
	player._hit = {"hit": true, "block": Vector3i(8, 8, 8), "normal": Vector3i.UP,
		"block_id": BlockDB.STONE}
	h.check(player.place_selected(), "the player can place a rotated ridge")
	h.eq(world.get_block(Vector3i(8, 9, 8)), SLATE_RIDGE, "placement writes the ridge id")
	h.eq(world.get_orientation(Vector3i(8, 9, 8)), 1, "placement writes the ridge axis")

	player.inventory.add(SLATE_SLAB, 2)
	h.check(_select(player.inventory, SLATE_SLAB), "the slate slab is selectable")
	player.placement_facing = -1
	h.eq(player.rotate_placement(), 0, "R starts the slab at the +Z facing")
	h.eq(player.rotate_placement(), 1, "R cycles the slab to +X")
	player.placement_facing = 0
	player._hit = {"hit": true, "block": Vector3i(10, 8, 8), "normal": Vector3i.UP,
		"block_id": BlockDB.STONE}
	h.check(player.place_selected(), "the player can place a bottom slab")
	h.eq(world.get_orientation(Vector3i(10, 9, 8)), 0, "a top-face hit places a bottom slab")
	player._hit = {"hit": true, "block": Vector3i(12, 8, 8), "normal": Vector3i.DOWN,
		"block_id": BlockDB.STONE}
	h.check(player.place_selected(), "the player can place an upside-down slab")
	h.eq(world.get_orientation(Vector3i(12, 7, 8)), 4, "an underside hit places a top slab")

	player.inventory.add(RAMP, 2)
	h.check(_select(player.inventory, RAMP), "the slate ramp is selectable")
	player.placement_facing = -1
	h.eq(player.rotate_placement(), 0, "R starts the ramp at the +Z facing")
	h.eq(player.rotate_placement(), 1, "R cycles the ramp to +X")
	h.eq(player.rotate_placement(), 2, "R cycles the ramp to -Z")
	h.eq(player.rotate_placement(), 3, "R cycles the ramp to -X")
	player.placement_facing = 0
	player._hit = {"hit": true, "block": Vector3i(14, 8, 8), "normal": Vector3i.UP,
		"block_id": BlockDB.STONE}
	h.check(player.place_selected(), "the player can place a slate ramp")
	h.eq(world.get_orientation(Vector3i(14, 9, 8)), 0, "the ramp keeps its horizontal facing")
	player._hit = {"hit": true, "block": Vector3i(14, 8, 8), "normal": Vector3i.DOWN,
		"block_id": BlockDB.STONE}
	h.eq(player.placement_orientation(Vector3i.DOWN), 0,
		"a downward hit does not turn a ramp upside down")
	h.check(not world.set_block_state(Vector3i(14, 9, 8), RAMP, 4),
		"ramp orientations above three are refused")

	player.inventory.add(PLASTER, 1)
	h.check(_select(player.inventory, PLASTER), "plaster is selectable")
	h.eq(player.rotate_placement(), -1, "R refuses a non-orientable block")
	h.check(VoxelPlayer.orientation_label(SLATE_RIDGE, 0).contains("X"),
		"the HUD label names the ridge's X axis")
	h.check(VoxelPlayer.orientation_label(SLATE_RIDGE, 1).contains("Z"),
		"the HUD label names the ridge's Z axis")
	h.check(VoxelPlayer.orientation_label(SLATE_SLAB, 4).contains("upside down"),
		"the HUD label marks an upside-down slab")
	h.check(VoxelPlayer.orientation_label(RAMP, 1).contains("+X"),
		"the HUD label names the ramp's facing")

	# Ridge orientation round-trips through world data and the save file.
	h.check(world.set_block_state(Vector3i(14, 9, 8), SLATE_RIDGE, 3),
		"an oriented ridge can be written")
	h.eq(world.get_orientation(Vector3i(14, 9, 8)), 3, "the ridge orientation is stored")
	h.check(not world.set_block_state(Vector3i(14, 8, 8), PLASTER, 2),
		"a non-orientable block rejects an orientation")

	var saves := SaveManager.new("user://m29_architecture_test")
	_clean_save_directory(saves)
	var save_world := VoxelWorld.new(17017)
	var save_chunk := ChunkData.new(Vector3i.ZERO)
	save_chunk.generated = true
	save_world.adopt_chunk(save_chunk)
	var ridge_cell := Vector3i(4, 9, 4)
	var stair_cell := Vector3i(6, 9, 4)
	var slab_cell := Vector3i(8, 9, 4)
	var ramp_cell := Vector3i(10, 9, 4)
	h.check(save_world.set_block_state(ridge_cell, SLATE_RIDGE, 3), "saves an oriented ridge")
	h.check(save_world.set_block_state(stair_cell, SLATE_STAIR, 6), "saves an oriented slate stair")
	h.check(save_world.set_block_state(slab_cell, SLATE_SLAB, 4), "saves an upside-down slab")
	h.check(save_world.set_block_state(ramp_cell, RAMP, 2), "saves an oriented slate ramp")
	h.check(saves.write(save_world, null, null, null, null, Survival.MAX_BREATH, Survival.MAX_HUNGER),
		"writes the M29 save")
	var read_back: Dictionary = saves.read()
	h.check(bool(read_back.get("ok", false)), "reads the M29 save back")
	var restored := VoxelWorld.new(17017)
	var applied: Dictionary = saves.apply(read_back, restored, null, null)
	h.check(bool(applied.get("ok", false)), "applies the M29 save")
	restored.ensure_chunk(Vector3i.ZERO)
	h.eq(restored.get_block(ridge_cell), SLATE_RIDGE, "the ridge survives save/load")
	h.eq(restored.get_orientation(ridge_cell), 3, "the ridge orientation survives save/load")
	h.eq(restored.get_orientation(stair_cell), 6, "the slate stair orientation survives save/load")
	h.eq(restored.get_orientation(slab_cell), 4, "the upside-down slab survives save/load")
	h.eq(restored.get_block(ramp_cell), RAMP, "the slate ramp survives save/load")
	h.eq(restored.get_orientation(ramp_cell), 2, "the ramp orientation survives save/load")
	h.check(saves._sanitise_block_rows([[0, 8, 0, RAMP, 3]], SaveManager.VERSION) != null,
		"the save validator accepts a horizontal ramp orientation")
	h.check(saves._sanitise_block_rows([[0, 8, 0, RAMP, 4]], SaveManager.VERSION) == null,
		"the save validator rejects an upside-down ramp orientation")
	h.check(saves._sanitise_block_rows([[0, 8, 0, SLATE_RIDGE, 1]], SaveManager.VERSION) != null,
		"the save validator accepts orientation on a ridge")
	h.check(saves._sanitise_block_rows([[0, 8, 0, PLASTER, 1]], SaveManager.VERSION) == null,
		"the save validator rejects orientation on plaster")
	_clean_save_directory(saves)

	tree.root.remove_child(player)
	player.free()


func _select(inventory: Inventory, item_id: int) -> bool:
	for index in Inventory.HOTBAR_SIZE:
		if inventory.slots[index] == item_id and inventory.counts[index] > 0:
			if index == inventory.selected:
				return true
			return inventory.select(index)
	return false


func _clean_save_directory(saves: SaveManager) -> void:
	var directory := DirAccess.open(saves.directory)
	if directory == null:
		return
	for file_name: String in directory.get_files():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(saves.directory.path_join(file_name)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(saves.directory))


func _demos(h: TestHarness) -> void:
	var kit_script: Variant = load("res://scripts/game/medieval_kit.gd")
	h.check(kit_script != null and kit_script is GDScript, "the reusable medieval kit exists")
	if kit_script == null or not (kit_script is GDScript):
		return
	var roof_world := VoxelWorld.new(17017)
	var roof_chunk := ChunkData.new(Vector3i.ZERO)
	roof_chunk.generated = true
	roof_world.adopt_chunk(roof_chunk)
	var anchor := Vector3i(8, 8, 8)
	var report: Dictionary = kit_script.build_gable_roof(roof_world, anchor, 2, 2, 2,
		{"finials": true, "chimney": {"x": 1, "z": -1, "top": 6}})
	h.eq(int(report["slabs"]), 14, "the roof helper lays the full eave overhang")
	h.eq(int(report["ramps"]), 20, "the roof helper lays two continuous ramp planes")
	h.eq(int(report["ridges"]), 5, "the roof helper closes the ridge")
	h.check(int(report["gable"]) > 0, "the roof helper fills the gable ends")
	h.eq(int(report["finials"]), 2, "the roof helper places two finials")
	h.check(int(report["chimney"]) > 0, "the roof helper raises the chimney")
	h.eq(roof_world.get_block(anchor + Vector3i(0, 1, 3)), SLATE_SLAB,
		"the +Z eave is a thin slate slab flush with the wall top")
	h.eq(roof_world.get_orientation(anchor + Vector3i(0, 1, 3)), 4,
		"the eave slab is an upper-half slab")
	h.eq(roof_world.get_block(anchor + Vector3i(0, 2, 2)), RAMP,
		"the first +Z slope row is a slate ramp")
	h.eq(roof_world.get_orientation(anchor + Vector3i(0, 2, 2)), 0,
		"the +Z ramp rises toward the ridge")
	h.eq(roof_world.get_block(anchor + Vector3i(0, 2, -2)), RAMP,
		"the first -Z slope row is a slate ramp")
	h.eq(roof_world.get_orientation(anchor + Vector3i(0, 2, -2)), 2,
		"the -Z ramp is mirrored")
	h.eq(roof_world.get_block(anchor + Vector3i(0, 4, 0)), SLATE_RIDGE,
		"the roof is closed by a slate ridge")
	h.eq(roof_world.get_orientation(anchor + Vector3i(0, 4, 0)), 0,
		"the ridge runs along X")
	h.eq(roof_world.get_block(anchor + Vector3i(2, 2, 0)), PLASTER,
		"the gable end has a plaster infill panel")
	h.eq(roof_world.get_block(anchor + Vector3i(2, 2, 1)), TIMBER_BRACE,
		"the gable end has a diagonal timber brace")
	h.eq(roof_world.get_block(anchor + Vector3i(2, 5, 0)), FINIAL,
		"the ridge end carries a finial")
	h.eq(roof_world.get_block(anchor + Vector3i(1, 6, -1)), CHIMNEY,
		"the chimney rises above the ridge")

	# The M25 cottage is the starter house as well, so this covers both.  The
	# builder caps its levelled base so the fixed site also fits on v3 highlands.
	var build_world := VoxelWorld.new(17017)
	var build_report: Dictionary = BuildDemo.build(build_world)
	h.check(int(build_report["cottage"]) > 180, "the M25 cottage is rebuilt with the M29 palette")
	var base: Vector3i = build_report["base_y"]
	var cottage := base + Vector3i(BuildDemo.COTTAGE_OFFSET.x, 0, BuildDemo.COTTAGE_OFFSET.y)
	h.eq(build_world.get_block(cottage + Vector3i(0, 1, 3)), BlockDB.DOOR, "the cottage keeps its door")
	h.eq(build_world.get_block(cottage + Vector3i(1, 1, 3)), DARK_TIMBER,
		"the door has a dark timber surround")
	h.eq(build_world.get_block(cottage + Vector3i(0, 2, -3)), WINDOW,
		"the cottage has framed windows")
	h.eq(build_world.get_block(cottage + Vector3i(1, 2, -3)), SHUTTER,
		"the windows have shutters")
	h.eq(build_world.get_block(cottage + Vector3i(2, 2, -3)), TIMBER_BRACE,
		"the walls have timber braces")
	h.eq(build_world.get_block(cottage + Vector3i(3, 3, -3)), PLASTER,
		"the upper wall is warm plaster between dark posts")
	h.eq(build_world.get_block(cottage + Vector3i(0, 3, 4)), SLATE_SLAB,
		"the cottage has a thin eave overhang")
	h.eq(build_world.get_orientation(cottage + Vector3i(0, 3, 4)), 4,
		"the cottage eave is flush with the wall top")
	h.eq(build_world.get_block(cottage + Vector3i(0, 4, 3)), RAMP,
		"the cottage roof starts with slate ramps")
	h.eq(build_world.get_orientation(cottage + Vector3i(0, 4, 3)), 0,
		"the cottage south slope rises toward the ridge")
	h.eq(build_world.get_block(cottage + Vector3i(0, 7, 0)), SLATE_RIDGE,
		"the cottage roof is closed by a slate ridge")
	h.eq(build_world.get_block(cottage + Vector3i(4, 5, 0)), PLASTER,
		"the cottage gable is plaster-infilled")
	h.eq(build_world.get_block(cottage + Vector3i(3, 9, -2)), CHIMNEY,
		"the cottage has a stone chimney above the roof")
	h.eq(build_world.get_block(cottage + Vector3i(3, 1, 4)), FLOWER_BOX,
		"the cottage has a flower box under a window")
	h.eq(build_world.get_block(cottage + Vector3i(4, 8, 0)), FINIAL,
		"the cottage ridge ends carry finials")
	h.eq(build_world.get_block(cottage + Vector3i(-3, 1, -2)), BlockDB.CRAFTING_TABLE,
		"the cottage is still furnished")
	h.check(build_world.set_block(cottage + Vector3i(4, 1, 0), BlockDB.AIR),
		"the stone plinth is mineable")
	h.check(build_world.set_block_state(cottage + Vector3i(0, 4, 3), BlockDB.AIR, 0),
		"a slate roof ramp is mineable")

	# Starter house shares the same cottage, with the door facing the spawn.
	var starter_world := VoxelWorld.new(17017)
	var spawn := Vector2i(8, 8)
	var spawn_height := starter_world.generator.height_at(spawn.x, spawn.y)
	for dz in range(-4, 5):
		for dx in range(-4, 5):
			starter_world.ensure_chunk(VoxelWorld.world_to_chunk(
				Vector3i(spawn.x + dx, spawn_height, spawn.y + dz)))
	var starter_report: Dictionary = StarterHouse.build(starter_world, spawn)
	h.check(int(starter_report["house"]) > 180, "the starter house places the rebuilt cottage")
	var starter_anchor := Vector3i(spawn.x + StarterHouse.OFFSET.x, spawn_height, spawn.y + StarterHouse.OFFSET.y)
	h.eq(starter_world.get_block(starter_anchor + Vector3i(0, 1, 3)), BlockDB.DOOR,
		"the starter house door faces the spawn")
	h.eq(starter_world.get_block(starter_anchor + Vector3i(0, 2, -3)), WINDOW,
		"the starter house has framed windows")
	h.eq(starter_world.get_block(starter_anchor + Vector3i(0, 4, 3)), RAMP,
		"the starter house has a slate roof")
	h.eq(starter_world.get_block(starter_anchor + Vector3i(0, 7, 0)), SLATE_RIDGE,
		"the starter house roof is closed by a slate ridge")
	h.check(starter_world.set_block(starter_anchor + Vector3i(0, 1, 3), BlockDB.AIR),
		"the starter house door is still editable")

	# Final showcase: the longhouse, market row and keep use the same roof kit.
	# It must also fit on the current v3 highlands, not only the old fixed site.
	var final_world := VoxelWorld.new(17017)
	var final_report: Dictionary = FinalDemo.build(final_world)
	h.check(int(final_report["longhouse"]) > 250, "the longhouse is rebuilt with the new palette")
	h.check(int(final_report["market"]) > 70, "the market stalls are rebuilt")
	h.check(int(final_report["castle"]) > 420, "the castle keeps its full structure")
	var final_base: Vector3i = final_report["base_y"]
	var longhouse := final_base + Vector3i(FinalDemo.LONGHOUSE_OFFSET.x, 0, FinalDemo.LONGHOUSE_OFFSET.y)
	var market := final_base + Vector3i(FinalDemo.MARKET_OFFSET.x, 0, FinalDemo.MARKET_OFFSET.y)
	var castle := final_base + Vector3i(FinalDemo.CASTLE_OFFSET.x, 0, FinalDemo.CASTLE_OFFSET.y)
	h.eq(final_world.get_block(longhouse + Vector3i(0, 3, 5)), SLATE_SLAB,
		"the longhouse has a thin eave")
	h.eq(final_world.get_block(longhouse + Vector3i(0, 4, 4)), RAMP,
		"the longhouse has a continuous slate ramp roof")
	h.eq(final_world.get_block(longhouse + Vector3i(0, 8, 0)), SLATE_RIDGE,
		"the longhouse ridge runs along its length")
	h.eq(final_world.get_block(longhouse + Vector3i(4, 2, -4)), WINDOW,
		"the longhouse has framed windows")
	h.eq(final_world.get_block(longhouse + Vector3i(5, 8, -2)), CHIMNEY,
		"the longhouse has a chimney")
	h.eq(final_world.get_block(longhouse + Vector3i(4, 2, 4)), SHUTTER,
		"the longhouse has louvered shutters")
	h.eq(final_world.get_block(market + Vector3i(0, 2, 3)), SLATE_SLAB,
		"the market stalls have thin slate eaves")
	h.eq(final_world.get_block(market + Vector3i(0, 3, 2)), RAMP,
		"the market stalls have continuous slate ramps")
	h.eq(final_world.get_block(market + Vector3i(0, 5, 0)), SLATE_RIDGE,
		"the market stalls have slate ridges")
	h.eq(final_world.get_block(castle + Vector3i(0, 9, 0)), SLATE_RIDGE,
		"the keep is closed by a slate ridge")
	h.eq(final_world.get_block(castle + Vector3i(0, 4, 4)), WINDOW,
		"the keep has a framed upper window")
	h.eq(final_world.get_block(castle + Vector3i(4, 10, 0)), FINIAL,
		"the keep ridge ends carry finials")
	h.eq(final_world.get_block(castle + Vector3i(0, 1, 8)), BlockDB.DOOR,
		"the castle gate still works")
	h.check(final_world.set_block(castle + Vector3i(8, 2, 0), BlockDB.AIR),
		"a castle wall block is still mineable")
	h.check(final_world.set_block_state(longhouse + Vector3i(0, 4, 4), BlockDB.AIR, 0),
		"a longhouse roof ramp is mineable")


func _all_uv2(mesh: ArrayMesh) -> PackedVector2Array:
	var result := PackedVector2Array()
	if mesh == null:
		return result
	for surface_index in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface_index)
		result.append_array(arrays[Mesh.ARRAY_TEX_UV2] as PackedVector2Array)
	return result


func _bad_winding(arrays: Array) -> int:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var bad := 0
	var i := 0
	while i + 2 < indices.size():
		var a := int(indices[i])
		var b := int(indices[i + 1])
		var c := int(indices[i + 2])
		var geometric: Vector3 = (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
		var outward: Vector3 = normals[a] + normals[b] + normals[c]
		if geometric.dot(outward) >= 0.0:
			bad += 1
		i += 3
	return bad


func _bad_collision_winding(collision: ArrayMesh, centre: Vector3) -> int:
	var vertices: PackedVector3Array = collision.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = collision.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	var bad := 0
	var i := 0
	while i + 2 < indices.size():
		var a := vertices[int(indices[i])]
		var b := vertices[int(indices[i + 1])]
		var c := vertices[int(indices[i + 2])]
		var geometric: Vector3 = (b - a).cross(c - a)
		if geometric.dot((a + b + c) / 3.0 - centre) >= 0.0:
			bad += 1
		i += 3
	return bad

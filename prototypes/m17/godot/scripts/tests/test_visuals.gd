extends RefCounted

## M18 visual regressions: custom station models, baked vertex AO, grass face
## tinting, runtime tree planting, boulder generation and the day/night sky
## curves.  These pin the behaviour the visual pass depends on, without needing a
## windowed capture.


func name() -> String:
	return "M18 visuals"


var _library: TextureLibrary
var _materials: VoxelMaterials
var _mesher: ChunkMesher


func _setup() -> void:
	if _mesher != null:
		return
	_library = TextureLibrary.new()
	_library.load_all()
	_materials = VoxelMaterials.new(_library)
	_mesher = ChunkMesher.new(_library, _materials)


func _make_chunk(world: VoxelWorld, coord: Vector3i) -> ChunkData:
	var chunk := ChunkData.new(coord)
	chunk.generated = true
	world.adopt_chunk(chunk)
	return chunk


func _surface_arrays(result: Dictionary) -> Array:
	var mesh: ArrayMesh = result["mesh"]
	if mesh == null or mesh.get_surface_count() == 0:
		return []
	return mesh.surface_get_arrays(0)


func run(h: TestHarness) -> void:
	_setup()
	h.check(_mesher != null, "creates a mesher")

	_stations(h)
	_ambient_occlusion(h)
	_grass_tint(h)
	_planted_trees(h)
	_boulders(h)
	_visual_arena(h)
	_sky_curves(h)

	h.finish()


## The crafting table and furnace are real models: more than the twelve faces two
## cubes would use, a glow flag on the furnace opening, geometry inside the voxel
## cell, and a full-cube collision shape.
func _stations(h: TestHarness) -> void:
	h.section("station models")
	h.eq(_mesher.face_layer[BlockDB.CRAFTING_TABLE * 6 + BlockDB.FACE_PY],
		_library.layer_index("crafting_table_top"), "the crafting table top resolves to its own texture")
	h.eq(_mesher.face_layer[BlockDB.FURNACE * 6 + BlockDB.FACE_PY],
		_library.layer_index("furnace_top"), "the furnace top resolves to its own texture")

	var world := VoxelWorld.new(17017)
	var chunk := _make_chunk(world, Vector3i.ZERO)
	chunk.blocks[ChunkData.cell_index(4, 8, 4)] = BlockDB.CRAFTING_TABLE
	chunk.blocks[ChunkData.cell_index(8, 8, 8)] = BlockDB.FURNACE
	var result := _mesher.build(chunk, world)
	h.greater(float(result["faces"]), 12.0, "stations emit more than two cube's worth of faces (%d)" % int(result["faces"]))

	# Collision is still the full cube on all six exposed faces of each station.
	var collision: ArrayMesh = result["collision"]
	h.check(collision != null, "stations still produce a collision mesh")
	var collision_arrays: Array = collision.surface_get_arrays(0)
	h.eq((collision_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), 48,
		"two isolated stations keep 24 collision vertices each")
	h.eq((collision_arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), 72,
		"two isolated stations keep 36 collision indices each")

	var arrays := _surface_arrays(result)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	h.greater(float(vertices.size()), 0.0, "station geometry reaches the mesh")
	var inside := true
	var glowing := 0
	for index in vertices.size():
		var vertex: Vector3 = vertices[index]
		var cell := Vector3(floor(vertex.x), floor(vertex.y), floor(vertex.z))
		if not (cell.is_equal_approx(Vector3(4, 8, 4)) or cell.is_equal_approx(Vector3(8, 8, 8))):
			inside = false
		if uv2[index].y > 0.5:
			glowing += 1
	h.check(inside, "station geometry stays inside its own voxel cell")
	h.greater(float(glowing), 0.0, "the furnace opening carries the glow flag (%d vertices)" % glowing)


## Baked AO darkens a corner next to solid neighbours, and every vertex colour
## differs from flat white because of the per-block variation term.
func _ambient_occlusion(h: TestHarness) -> void:
	h.section("baked ambient occlusion")
	var world := VoxelWorld.new(17017)
	var chunk := _make_chunk(world, Vector3i.ZERO)
	# A stone corner: the block at (8, 8, 8) has solid neighbours on +X and +Z.
	chunk.blocks[ChunkData.cell_index(8, 8, 8)] = BlockDB.STONE
	chunk.blocks[ChunkData.cell_index(9, 8, 8)] = BlockDB.STONE
	chunk.blocks[ChunkData.cell_index(8, 8, 9)] = BlockDB.STONE
	var result := _mesher.build(chunk, world)
	var arrays := _surface_arrays(result)
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var darkest := 1.0
	for color in colors:
		darkest = minf(darkest, color.r)
	h.less(darkest, 0.9, "a corner next to solid neighbours is darkened (%.2f)" % darkest)

	# A lone block still varies per cell, so the surface is not one flat colour.
	var world2 := VoxelWorld.new(17017)
	var chunk2 := _make_chunk(world2, Vector3i.ZERO)
	chunk2.blocks[ChunkData.cell_index(8, 8, 8)] = BlockDB.STONE
	var result2 := _mesher.build(chunk2, world2)
	var colors2: PackedColorArray = _surface_arrays(result2)[Mesh.ARRAY_COLOR]
	h.check(colors2[0] != Color.WHITE, "opaque vertices carry per-block variation")


## Grass is biome-tinted on its top face only; the dirt sides stay neutral.
func _grass_tint(h: TestHarness) -> void:
	h.section("grass face tinting")
	var world := VoxelWorld.new(17017)
	var chunk := _make_chunk(world, Vector3i.ZERO)
	chunk.blocks[ChunkData.cell_index(8, 8, 8)] = BlockDB.GRASS
	var result := _mesher.build(chunk, world)
	var arrays := _surface_arrays(result)
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	# Normals survive the ArrayMesh as compressed values, so compare direction
	# rather than exact equality.
	var top_green := false
	var side_neutral := true
	for index in normals.size():
		var color: Color = colors[index]
		if normals[index].y > 0.5:
			if color.g > color.r and color.g > color.b:
				top_green = true
		elif normals[index].y < -0.5:
			pass
		elif absf(color.r - color.g) < 0.06 and absf(color.g - color.b) < 0.06:
			pass
		else:
			side_neutral = false
	h.check(top_green, "the grass top is biome tinted")
	h.check(side_neutral, "grass sides stay neutral dirt rather than green slabs")


## `WorldGen.plant_tree` uses the production shapes, is deterministic and lands
## inside the tree's footprint.
func _planted_trees(h: TestHarness) -> void:
	h.section("planted trees")
	var world := VoxelWorld.new(17017)
	for chunk_y in range(3, 7):
		world.ensure_chunk(Vector3i(0, chunk_y, 0))
	var touched := world.generator.plant_tree(world, 8, 8, WorldGen.TreeType.OAK)
	h.greater(float(touched), 0.0, "planting an oak touches at least one chunk")
	var logs := 0
	var leaves := 0
	for y in range(66, 96):
		if world.get_block(Vector3i(8, y, 8)) == BlockDB.OAK_LOG:
			logs += 1
	for dz in range(-4, 5):
		for dx in range(-4, 5):
			for y in range(66, 96):
				if world.get_block(Vector3i(8 + dx, y, 8 + dz)) == BlockDB.OAK_LEAVES:
					leaves += 1
	h.greater(float(logs), 2.0, "a planted oak has a trunk")
	h.greater(float(leaves), 5.0, "a planted oak has a canopy")

	var again := VoxelWorld.new(17017)
	for chunk_y in range(3, 7):
		again.ensure_chunk(Vector3i(0, chunk_y, 0))
	again.generator.plant_tree(again, 8, 8, WorldGen.TreeType.OAK)
	h.eq(world.fingerprint(), again.fingerprint(), "planting the same tree twice produces identical voxels")

	var pine := VoxelWorld.new(17017)
	for chunk_y in range(3, 7):
		pine.ensure_chunk(Vector3i(0, chunk_y, 0))
	pine.generator.plant_tree(pine, 8, 8, WorldGen.TreeType.PINE)
	var pine_logs := 0
	for y in range(60, 100):
		if pine.get_block(Vector3i(8, y, 8)) == BlockDB.PINE_LOG:
			pine_logs += 1
	h.greater(float(pine_logs), 2.0, "a planted pine has a taller trunk")

	# M22 tree library: birch and blossom use their own log/leaf blocks and keep
	# the deterministic production shapes.
	var birch := VoxelWorld.new(17017)
	for chunk_y in range(3, 7):
		birch.ensure_chunk(Vector3i(0, chunk_y, 0))
		birch.generator.plant_tree(birch, 10, 10, WorldGen.TreeType.BIRCH, 66)
	var birch_logs := 0
	var birch_leaves := 0
	for y in range(67, 96):
		var block_id := birch.get_block(Vector3i(10, y, 10))
		if block_id == BlockDB.BIRCH_LOG:
			birch_logs += 1
	for dz in range(-4, 5):
		for dx in range(-4, 5):
			for y in range(67, 96):
				if birch.get_block(Vector3i(10 + dx, y, 10 + dz)) == BlockDB.BIRCH_LEAVES:
					birch_leaves += 1
	h.greater(float(birch_logs), 2.0, "a planted birch has a pale trunk")
	h.greater(float(birch_leaves), 5.0, "a planted birch has its own leaves")

	var blossom := VoxelWorld.new(17017)
	for chunk_y in range(3, 7):
		blossom.ensure_chunk(Vector3i(0, chunk_y, 0))
	blossom.generator.plant_tree(blossom, 12, 12, WorldGen.TreeType.BLOSSOM, 66)
	var blossom_leaves := 0
	for dz in range(-4, 5):
		for dx in range(-4, 5):
			for y in range(67, 96):
				if blossom.get_block(Vector3i(12 + dx, y, 12 + dz)) == BlockDB.BLOSSOM_LEAVES:
					blossom_leaves += 1
	h.greater(float(blossom_leaves), 5.0, "a blossom tree uses the pink accent canopy")


## Boulders are sparse but present: some exposed cobble/mossy stone above the
## surface material in a bounded scan.
func _boulders(h: TestHarness) -> void:
	h.section("boulder generation")
	var world := VoxelWorld.new(17017)
	var found := 0
	for z in range(-64, 65, 4):
		for x in range(-64, 65, 4):
			var height := world.surface_height(x, z)
			if height <= WorldGen.SEA_LEVEL:
				continue
			world.ensure_chunk(VoxelWorld.world_to_chunk(Vector3i(x, height + 1, z)))
			for y in range(height + 1, height + 4):
				var block_id := world.get_block(Vector3i(x, y, z))
				if block_id == BlockDB.COBBLESTONE or block_id == BlockDB.MOSSY_COBBLE:
					found += 1
	h.greater(float(found), 0.0, "boulders appear as exposed rock above the surface (%d cells)" % found)


## The reproducible M22 showcase builds from the production world and contains
## the settlement, path, bridge, lanterns and vegetation the captures must show.
func _visual_arena(h: TestHarness) -> void:
	h.section("visual test area")
	var world := VoxelWorld.new(17017)
	# The arena spans the four-by-four chunk footprint around its centre.
	for chunk_z in range(-8, -3):
		for chunk_x in range(3, 7):
			for chunk_y in range(3, 6):
				world.ensure_chunk(Vector3i(chunk_x, chunk_y, chunk_z))
	var report := VisualTestArena.new().build(world)
	h.greater(float(report["blocks"]), 1000.0, "the visual test area places a substantial scene")
	h.greater(float(report["chunks"]), 0.0, "the visual test area touches loaded chunks")
	h.greater(float(report["cottage"]), 200.0, "the cottage definition writes a full building")
	h.greater(float(report["stall"]), 20.0, "the market stall definition writes a work area")
	h.greater(float(report["path"]), 30.0, "the path is a real winding route")
	h.greater(float(report["bridge"]), 5.0, "the bridge is placed")
	h.greater(float(report["lanterns"]), 3.0, "several lanterns are placed")
	h.greater(float(report["trees"]), 2.0, "several custom trees are planted")
	h.greater(float(report["decorations"]), 10.0, "flowers and ground cover are scattered")
	var floor_y := VisualTestArena.FLOOR_Y
	# M23: the pavilion roof is built from oriented stair blocks and a ridge cap.
	h.greater(float(report["stairs"]), 10.0, "the showcase builds a stair roof")
	var pavilion := Vector3i(VisualTestArena.CENTER.x + VisualTestArena.PAVILION_ANCHOR.x,
		floor_y, VisualTestArena.CENTER.z + VisualTestArena.PAVILION_ANCHOR.y)
	h.eq(world.get_block(pavilion + Vector3i(0, 5, 2)), BlockDB.STAIR,
		"the pavilion roof uses stair blocks")
	h.eq(world.get_orientation(pavilion + Vector3i(0, 5, 2)), 0,
		"the south roof slope rises toward the ridge")
	h.eq(world.get_orientation(pavilion + Vector3i(0, 5, -2)), 2,
		"the north roof slope is the mirror orientation")
	h.eq(world.get_block(pavilion + Vector3i(0, 6, 0)), BlockDB.ROOF_RIDGE,
		"the pavilion roof is closed by a ridge")
	h.eq(world.get_block(Vector3i(VisualTestArena.CENTER.x - 2, floor_y + 4, VisualTestArena.CENTER.z - 12)),
		BlockDB.ROOF_TILE, "the cottage has a tiled roof")
	h.eq(world.get_block(Vector3i(VisualTestArena.CENTER.x - 6, floor_y + 2, VisualTestArena.CENTER.z - 6)),
		BlockDB.DOOR, "the cottage front has a door")
	var lanterns := 0
	for z in range(-14, 15, 2):
		for x in range(-14, 15, 2):
			if world.get_block(Vector3i(VisualTestArena.CENTER.x + x, floor_y + 2, VisualTestArena.CENTER.z + z)) == BlockDB.LANTERN:
				lanterns += 1
	h.greater(float(lanterns), 0.0, "lantern blocks exist in the showcase")
	var pond := Vector3i(VisualTestArena.CENTER.x + VisualTestArena.POND_MIN.x,
		VisualTestArena.CENTER.y, VisualTestArena.CENTER.z + VisualTestArena.POND_MIN.y)
	h.eq(world.get_block(pond), BlockDB.WATER, "the area contains a water source")
	h.check(world.is_water_source(pond), "the pond water is a real fluid source")
	h.eq(world.get_block(Vector3i(VisualTestArena.CENTER.x, VisualTestArena.BASE_Y + 8, VisualTestArena.CENTER.z)),
		BlockDB.AIR, "the clearing above the path is open")


## The new sky curves are bounded and land where the renderer expects them.
func _sky_curves(h: TestHarness) -> void:
	h.section("sky curves")
	var noon := DayNight.new(0.25)
	var sunrise := DayNight.new(0.0)
	var sunset := DayNight.new(0.5)
	var night := DayNight.new(0.75)
	h.approx(sunrise.horizon_warmth(), 1.0, 1e-6, "sunrise is fully warm at the horizon")
	h.approx(sunset.horizon_warmth(), 1.0, 1e-6, "sunset is fully warm at the horizon")
	h.approx(noon.horizon_warmth(), 0.0, 1e-6, "noon has no sunset band")
	h.approx(night.horizon_warmth(), 0.0, 1e-6, "deep night has no sunset band")
	h.greater(night.star_amount(), 0.5, "stars are visible at midnight")
	h.approx(noon.star_amount(), 0.0, 1e-6, "no stars at noon")
	h.greater(noon.cloud_amount(), night.cloud_amount() - 0.001, "cloud cover is at least as strong by day")
	h.approx(noon.sunset_amount(), 0.0, 1e-6, "noon has no warm horizon band")

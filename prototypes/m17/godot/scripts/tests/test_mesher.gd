extends RefCounted

## Mesh construction: face culling, cross-chunk borders, water surfaces,
## decoration planes and derived collision.


func name() -> String:
	return "chunk mesher"


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
	# Empty chunk with no generated terrain, adopted so meshing has neighbours.
	var chunk := ChunkData.new(coord)
	chunk.generated = true
	world.adopt_chunk(chunk)
	return chunk


func run(h: TestHarness) -> void:
	_setup()
	h.check(_mesher != null, "creates a mesher")

	# 1) A single block in an empty chunk exposes exactly six faces.
	var world := VoxelWorld.new(17017)
	var chunk := _make_chunk(world, Vector3i.ZERO)
	chunk.blocks[ChunkData.cell_index(8, 8, 8)] = BlockDB.STONE
	var result := _mesher.build(chunk, world)
	h.eq(int(result["faces"]), 6, "an isolated block emits six faces")
	h.check(result["mesh"] != null, "produces a mesh for the solid layer")
	h.check(result["collision"] != null, "produces a collision mesh for solid blocks")

	# 2) Two adjacent blocks share the face between them.
	var world2 := VoxelWorld.new(17017)
	var chunk2 := _make_chunk(world2, Vector3i.ZERO)
	chunk2.blocks[ChunkData.cell_index(8, 8, 8)] = BlockDB.STONE
	chunk2.blocks[ChunkData.cell_index(9, 8, 8)] = BlockDB.STONE
	var result2 := _mesher.build(chunk2, world2)
	h.eq(int(result2["faces"]), 10, "two adjacent blocks emit ten faces")

	# 3) A full horizontal plate culls nothing but the borders.
	var world3 := VoxelWorld.new(17017)
	var chunk3 := _make_chunk(world3, Vector3i.ZERO)
	for z in ChunkData.SIZE:
		for x in ChunkData.SIZE:
			chunk3.blocks[ChunkData.cell_index(x, 4, z)] = BlockDB.STONE
	var result3 := _mesher.build(chunk3, world3)
	h.eq(int(result3["faces"]), 256 * 2 + 16 * 4, "a 16x16 plate emits top, bottom and side faces only")
	h.less(float(result3["ms"]), 250.0, "one chunk meshes in well under 250 ms")

	# 4) Cross-chunk border faces are culled against the neighbour chunk.
	var world4 := VoxelWorld.new(17017)
	var left := _make_chunk(world4, Vector3i.ZERO)
	left.blocks[ChunkData.cell_index(15, 8, 8)] = BlockDB.STONE
	var alone := _mesher.build(left, world4)
	h.eq(int(alone["faces"]), 6, "a block on an unloaded border keeps its outward face")
	var right := _make_chunk(world4, Vector3i(1, 0, 0))
	right.blocks[ChunkData.cell_index(0, 8, 8)] = BlockDB.STONE
	var left_result := _mesher.build(left, world4)
	h.eq(int(left_result["faces"]), 5, "the border face is culled once the neighbour is loaded")
	var right_result := _mesher.build(right, world4)
	h.eq(int(right_result["faces"]), 5, "the neighbouring chunk culls the opposite face too")

	# 5) Water renders in its own mesh, at the level-derived surface height.
	var world5 := VoxelWorld.new(17017)
	var chunk5 := _make_chunk(world5, Vector3i.ZERO)
	var water_index := ChunkData.cell_index(8, 8, 8)
	chunk5.blocks[water_index] = BlockDB.WATER
	chunk5.fluid[water_index] = ChunkData.SOURCE_LEVEL
	chunk5.sources[water_index] = 1
	var water_surface_index := ChunkData.cell_index(8, 9, 8)
	chunk5.blocks[water_surface_index] = BlockDB.WATER
	chunk5.fluid[water_surface_index] = 4
	var water_result := _mesher.build(chunk5, world5)
	h.check(water_result["mesh"] == null, "water does not appear in the solid mesh")
	h.check(water_result["water_mesh"] != null, "water gets its own mesh")
	h.check(water_result["collision"] == null, "water generates no collision")
	h.eq(water_result["water_mesh"].get_surface_count(), 1, "water mesh has a single water surface")
	var water_arrays: Array = water_result["water_mesh"].surface_get_arrays(0)
	var water_vertices: PackedVector3Array = water_arrays[Mesh.ARRAY_VERTEX]
	var water_normals: PackedVector3Array = water_arrays[Mesh.ARRAY_NORMAL]
	var highest := -INF
	var buried_tops := 0
	for vertex_index in water_vertices.size():
		var vertex: Vector3 = water_vertices[vertex_index]
		highest = maxf(highest, vertex.y)
		if water_normals[vertex_index].y > 0.5 and absf(vertex.y - 9.0) < 0.001:
			buried_tops += 1
	# The surface cell (local y = 9) holds level 4, so it is drawn half full.
	h.approx(highest, 9.0 + ChunkMesher.WATER_RENDER_HEIGHT * 0.5, 0.001, "the water surface follows the fluid level")
	h.eq(buried_tops, 0, "water under water does not draw its own surface")
	var water_uv2: PackedVector2Array = water_arrays[Mesh.ARRAY_TEX_UV2]
	h.greater(float(water_uv2[0].x), 0.0, "water vertices carry their animation layer")

	# 6) Decorations render as two crossed planes and never collide.
	var world6 := VoxelWorld.new(17017)
	var chunk6 := _make_chunk(world6, Vector3i.ZERO)
	chunk6.blocks[ChunkData.cell_index(4, 8, 4)] = BlockDB.GRASS_TUFT
	var deco_result := _mesher.build(chunk6, world6)
	h.eq(int(deco_result["faces"]), 2, "a decoration emits two crossed planes")
	h.check(deco_result["collision"] == null, "decorations add no collision")

	# 6b) Flowers use three planes and bushes four, so they keep a silhouette from
	# an orbiting camera.  A flower keeps its colour instead of a green multiply.
	var world6b := VoxelWorld.new(17017)
	var chunk6b := _make_chunk(world6b, Vector3i.ZERO)
	chunk6b.blocks[ChunkData.cell_index(4, 8, 4)] = BlockDB.FLOWER_RED
	chunk6b.blocks[ChunkData.cell_index(8, 8, 8)] = BlockDB.BUSH
	chunk6b.biomes[ChunkData.column_index(4, 4)] = WorldGen.Biome.FOREST
	var deco2 := _mesher.build(chunk6b, world6b)
	h.eq(int(deco2["faces"]), 3 + 4, "flowers emit three planes and bushes four")
	h.check(deco2["collision"] == null, "flowers and bushes add no collision")

	# 6c) Custom one-cell models (barrel/lantern/fence) emit real geometry and
	# keep the full-cube collision of a solid block.  The non-solid lantern does
	# not collide; the fence does.
	var world6c := VoxelWorld.new(17017)
	var chunk6c := _make_chunk(world6c, Vector3i.ZERO)
	chunk6c.blocks[ChunkData.cell_index(4, 8, 4)] = BlockDB.BARREL
	chunk6c.blocks[ChunkData.cell_index(8, 8, 8)] = BlockDB.FENCE
	chunk6c.blocks[ChunkData.cell_index(12, 8, 12)] = BlockDB.LANTERN
	var custom := _mesher.build(chunk6c, world6c)
	h.greater(float(custom["faces"]), 30.0, "custom models emit more than a cube's six faces")
	h.check(custom["collision"] != null, "solid custom models keep collision")
	var glow_vertices := 0
	var arrays_c: Array = custom["mesh"].surface_get_arrays(0)
	var custom_uv2: PackedVector2Array = arrays_c[Mesh.ARRAY_TEX_UV2]
	for value: Vector2 in custom_uv2:
		if value.y > 0.5:
			glow_vertices += 1
	h.greater(float(glow_vertices), 0.0, "the lantern panes carry the emissive flag")

	# 7) Biome tint reaches the vertices of tinted blocks.
	var world7 := VoxelWorld.new(17017)
	var chunk7 := _make_chunk(world7, Vector3i.ZERO)
	var grass_index := ChunkData.cell_index(8, 8, 8)
	chunk7.blocks[grass_index] = BlockDB.GRASS
	chunk7.biomes[ChunkData.column_index(8, 8)] = WorldGen.Biome.FOREST
	var tint_result := _mesher.build(chunk7, world7)
	var arrays: Array = tint_result["mesh"].surface_get_arrays(0)
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	h.check(colors.size() > 0, "solid mesh carries vertex colours")
	h.check(colors[0] != Color.WHITE, "grass vertices are tinted by their biome")

	# 8) Layout contract: vertex colour, uv, uv2 and index arrays all agree.
	var all_arrays: Array = result3["mesh"].surface_get_arrays(0)
	h.eq((all_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), (all_arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array).size(), "normals match vertex count")
	h.eq((all_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), (all_arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).size(), "uvs match vertex count")
	h.eq((all_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), (all_arrays[Mesh.ARRAY_TEX_UV2] as PackedVector2Array).size(), "uv2 matches vertex count")
	h.eq((all_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), (all_arrays[Mesh.ARRAY_COLOR] as PackedColorArray).size(), "colours match vertex count")
	h.eq((all_arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), 576 * 6, "index count matches six indices per face")

	# 9) Every layer is emitted in chunk-local space, so the chunk node's world
	# position is the only world offset.  Regression: water used to be emitted in
	# world space, which shifted it by the chunk origin.
	var world9 := VoxelWorld.new(17017)
	_make_chunk(world9, Vector3i.ZERO)
	var offset_chunk := _make_chunk(world9, Vector3i(1, 0, 0))
	var offset_index := ChunkData.cell_index(4, 8, 4)
	offset_chunk.blocks[offset_index] = BlockDB.STONE
	offset_chunk.blocks[ChunkData.cell_index(5, 8, 4)] = BlockDB.WATER
	offset_chunk.fluid[ChunkData.cell_index(5, 8, 4)] = ChunkData.SOURCE_LEVEL
	offset_chunk.sources[ChunkData.cell_index(5, 8, 4)] = 1
	var offset_result := _mesher.build(offset_chunk, world9)
	for key: String in ["mesh", "water_mesh", "collision"]:
		var layer_mesh: ArrayMesh = offset_result[key]
		h.check(layer_mesh != null, "%s exists in the offset chunk" % key)
		if layer_mesh == null:
			continue
		var maximum := -INF
		var minimum := INF
		for surface_index in layer_mesh.get_surface_count():
			var layer_arrays: Array = layer_mesh.surface_get_arrays(surface_index)
			for vertex: Vector3 in (layer_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				minimum = minf(minimum, vertex.x)
				maximum = maxf(maximum, vertex.x)
		h.greater(minimum, -0.001, "%s stays inside the chunk's local bounds" % key)
		h.less(maximum, 16.001, "%s is not shifted by the chunk origin" % key)

	# 10) The padded border buffer is reused between builds.  A slab whose
	# neighbour is missing must read as AIR, not as whatever the previous chunk
	# left behind -- otherwise a chunk on the edge of the loaded region gets a
	# wrong mesh that depends on the order the chunks were meshed in.
	var world10 := VoxelWorld.new(17017)
	var primed := _make_chunk(world10, Vector3i.ZERO)
	primed.blocks[ChunkData.cell_index(15, 8, 8)] = BlockDB.STONE
	var prime_neighbour := _make_chunk(world10, Vector3i(1, 0, 0))
	prime_neighbour.blocks[ChunkData.cell_index(0, 8, 8)] = BlockDB.STONE
	var primed_result := _mesher.build(primed, world10)
	h.eq(int(primed_result["faces"]), 5, "the priming build sees its loaded neighbour")

	var world10b := VoxelWorld.new(17017)
	var lone := _make_chunk(world10b, Vector3i.ZERO)
	lone.blocks[ChunkData.cell_index(15, 8, 8)] = BlockDB.STONE
	var reused_result := _mesher.build(lone, world10b)
	h.eq(int(reused_result["faces"]), 6, "a missing neighbour is not culled by stale padding from the previous build")
	var fresh := ChunkMesher.new(_library, _materials)
	var fresh_result := fresh.build(lone, world10b)
	h.eq(int(reused_result["faces"]), int(fresh_result["faces"]), "a reused mesher matches a freshly created one")

	# 11) Threaded meshing correctness: `capture_input` must freeze the voxel
	# state.  The streamer snapshots on the main thread and builds on a worker, so
	# an edit made after the snapshot must not change that snapshot's geometry --
	# and the next snapshot must see it.
	var world11 := VoxelWorld.new(17017)
	var snapshot_chunk := _make_chunk(world11, Vector3i.ZERO)
	snapshot_chunk.blocks[ChunkData.cell_index(15, 8, 8)] = BlockDB.STONE
	var snapshot_neighbour := _make_chunk(world11, Vector3i(1, 0, 0))
	snapshot_neighbour.blocks[ChunkData.cell_index(0, 8, 8)] = BlockDB.STONE
	var frozen := _mesher.capture_input(snapshot_chunk, world11)
	var frozen_faces := int(_mesher.build_geometry(frozen)["faces"])
	h.eq(frozen_faces, 5, "the snapshot build culls against the loaded neighbour")
	# Remove the neighbour block after the snapshot was taken.
	snapshot_neighbour.blocks[ChunkData.cell_index(0, 8, 8)] = BlockDB.AIR
	var frozen_again := int(_mesher.build_geometry(frozen)["faces"])
	h.eq(frozen_again, frozen_faces, "an edit after the snapshot does not change the snapshot's geometry")
	var recaptured := int(_mesher.build_geometry(_mesher.capture_input(snapshot_chunk, world11))["faces"])
	h.eq(recaptured, 6, "a fresh snapshot reflects the edit")

	# The chunk's dirty revision advances with every mark_dirty(), which is what
	# lets the streamer refuse to clear a dirty flag when an edit raced the build.
	var revision_before := snapshot_chunk.mesh_revision
	snapshot_chunk.mark_dirty()
	h.eq(snapshot_chunk.mesh_revision, revision_before + 1, "mark_dirty advances the mesh revision")

	h.finish()

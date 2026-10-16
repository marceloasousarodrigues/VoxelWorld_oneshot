class_name ChunkMesher
extends RefCounted

## Builds a chunk's render mesh and its derived collision mesh from logical
## voxel data.
##
## Design notes:
## - Only visible faces are emitted (a face is skipped when its neighbour hides
##   it), so interior faces never reach the GPU.
## - A padded 18^3 block copy is built first so border lookups against the six
##   neighbour chunks are plain index arithmetic instead of per-face world
##   queries.
## - Faces are grouped into five render layers (opaque, cutout, blend, water,
##   deco); each becomes one mesh surface with its own material.
## - Texture layer indices travel in `ARRAY_TEX_UV2.x`, vertex colour carries
##   face shading multiplied by biome tint.

const PAD := ChunkData.SIZE + 2
const PADDED_CELLS := PAD * PAD * PAD
const LAYER_CELLS := ChunkData.SIZE * ChunkData.SIZE

## Neighbour offset into the padded buffer for each face, in face order
## (PX, NX, PY, NY, PZ, NZ).  Using strides keeps the hottest loop free of
## per-face index arithmetic and function calls.
const FACE_STRIDE := [1, -1, PAD * PAD, -PAD * PAD, PAD, -PAD]

const FACE_NORMALS := [
	Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0),
	Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1),
]
const FACE_NORMAL_I := [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0),
	Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]
const FACE_CORNERS := [
	[Vector3(0.5, -0.5, -0.5), Vector3(0.5, 0.5, -0.5), Vector3(0.5, 0.5, 0.5), Vector3(0.5, -0.5, 0.5)],
	[Vector3(-0.5, -0.5, 0.5), Vector3(-0.5, 0.5, 0.5), Vector3(-0.5, 0.5, -0.5), Vector3(-0.5, -0.5, -0.5)],
	[Vector3(-0.5, 0.5, 0.5), Vector3(0.5, 0.5, 0.5), Vector3(0.5, 0.5, -0.5), Vector3(-0.5, 0.5, -0.5)],
	[Vector3(-0.5, -0.5, -0.5), Vector3(0.5, -0.5, -0.5), Vector3(0.5, -0.5, 0.5), Vector3(-0.5, -0.5, 0.5)],
	[Vector3(0.5, -0.5, 0.5), Vector3(0.5, 0.5, 0.5), Vector3(-0.5, 0.5, 0.5), Vector3(-0.5, -0.5, 0.5)],
	[Vector3(-0.5, -0.5, -0.5), Vector3(-0.5, 0.5, -0.5), Vector3(0.5, 0.5, -0.5), Vector3(0.5, -0.5, -0.5)],
]
const FACE_UVS := [
	[Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)],
	[Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)],
	[Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)],
	[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)],
	[Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)],
	[Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)],
]
const QUAD_INDICES := [0, 1, 2, 0, 2, 3]
## Face shading: top faces catch the most light, bottom faces the least.
const FACE_SHADE := [0.84, 0.84, 1.0, 0.52, 0.70, 0.70]
const WATER_RENDER_HEIGHT := 0.875
## Layers that make up the shadow-casting chunk mesh; water is a separate mesh
## so it never casts shadows and sorts independently.
const SOLID_LAYERS := [BlockDB.LAYER_OPAQUE, BlockDB.LAYER_CUTOUT, BlockDB.LAYER_BLEND, BlockDB.LAYER_DECO]

var library: TextureLibrary
var materials: VoxelMaterials
var face_layer: PackedInt32Array = PackedInt32Array()
var _buffers: Array = []
var _collision := {"vertex": PackedVector3Array(), "index": PackedInt32Array()}
var _padded: PackedByteArray = PackedByteArray()
var _padded_fluid: PackedByteArray = PackedByteArray()
var stats := {"builds": 0, "faces": 0, "triangles": 0, "ms": 0.0, "fill_ms": 0.0, "emit_ms": 0.0, "assemble_ms": 0.0}


func _init(texture_library: TextureLibrary, voxel_materials: VoxelMaterials = null) -> void:
	library = texture_library
	materials = voxel_materials if voxel_materials != null else VoxelMaterials.new(texture_library)
	_resolve_layers()
	for layer in BlockDB.LAYER_COUNT:
		_buffers.append(_empty_surface())
	_padded.resize(PADDED_CELLS)
	_padded_fluid.resize(PADDED_CELLS)


func _resolve_layers() -> void:
	face_layer.resize(BlockDB.COUNT * 6)
	for block_id in BlockDB.COUNT:
		var keys: PackedStringArray = BlockDB.face_keys[block_id]
		for face in 6:
			face_layer[block_id * 6 + face] = library.layer_index(keys[face]) if not keys[face].is_empty() else 0


func _empty_surface() -> Dictionary:
	return {
		"vertex": PackedVector3Array(),
		"normal": PackedVector3Array(),
		"uv": PackedVector2Array(),
		"uv2": PackedVector2Array(),
		"color": PackedColorArray(),
		"index": PackedInt32Array(),
		"faces": 0,
	}


static func padded_index(x: int, y: int, z: int) -> int:
	return (x + 1) + PAD * ((z + 1) + PAD * (y + 1))


## Builds the mesh.  Returns
## `{"mesh": ArrayMesh?, "collision": ArrayMesh?, "faces": int, "ms": float}`.
func build(chunk: ChunkData, world: VoxelWorld) -> Dictionary:
	var started := Time.get_ticks_usec()
	for surface: Dictionary in _buffers:
		surface["vertex"].clear()
		surface["normal"].clear()
		surface["uv"].clear()
		surface["uv2"].clear()
		surface["color"].clear()
		surface["index"].clear()
		surface["faces"] = 0
	_collision["vertex"].clear()
	_collision["index"].clear()

	_fill_padded(chunk, world)
	var after_fill := Time.get_ticks_usec()
	_emit_faces(chunk, world)
	var after_emit := Time.get_ticks_usec()

	var mesh := _build_array_mesh(SOLID_LAYERS)
	var water_mesh := _build_array_mesh([BlockDB.LAYER_WATER])
	var collision: ArrayMesh = null
	if not _collision["index"].is_empty():
		collision = ArrayMesh.new()
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _collision["vertex"]
		arrays[Mesh.ARRAY_INDEX] = _collision["index"]
		collision.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var elapsed := float(Time.get_ticks_usec() - started) / 1000.0
	stats["builds"] = int(stats["builds"]) + 1
	stats["ms"] = float(stats["ms"]) + elapsed
	stats["fill_ms"] = float(stats["fill_ms"]) + float(after_fill - started) / 1000.0
	stats["emit_ms"] = float(stats["emit_ms"]) + float(after_emit - after_fill) / 1000.0
	stats["assemble_ms"] = float(stats["assemble_ms"]) + float(Time.get_ticks_usec() - after_emit) / 1000.0
	var faces := 0
	for surface: Dictionary in _buffers:
		faces += int(surface["faces"])
	stats["faces"] = int(stats["faces"]) + faces
	stats["triangles"] = int(stats["triangles"]) + faces * 2
	return {"mesh": mesh, "water_mesh": water_mesh, "collision": collision, "faces": faces, "ms": elapsed}


func _fill_padded(chunk: ChunkData, world: VoxelWorld) -> void:
	var blocks := chunk.blocks
	var fluid := chunk.fluid
	# The padded buffer is reused between builds and only the interior plus the
	# slabs of *loaded* neighbours get overwritten below.  It must be reset first:
	# a slab whose neighbour is not loaded has to read as AIR (which only ever
	# draws extra faces), not as whatever the previously meshed chunk left there.
	# Without this reset the emitted geometry of a chunk on the edge of the loaded
	# region depends on the order the chunks happened to be meshed in.
	_padded.fill(BlockDB.AIR)
	_padded_fluid.fill(ChunkData.NO_FLUID)
	for local_y in ChunkData.SIZE:
		for local_z in ChunkData.SIZE:
			var row := ChunkData.cell_index(0, local_y, local_z)
			var padded_row := padded_index(0, local_y, local_z)
			for local_x in ChunkData.SIZE:
				_padded[padded_row + local_x] = blocks[row + local_x]
				_padded_fluid[padded_row + local_x] = fluid[row + local_x]
	var coord := chunk.coord
	for face in 6:
		var offset: Vector3i = FACE_NORMAL_I[face]
		var neighbour: ChunkData = world.chunks.get(coord + offset, null)
		if neighbour == null:
			continue
		_fill_padded_slab(neighbour.blocks, neighbour.fluid, face)


func _fill_padded_slab(neighbour_blocks: PackedByteArray, neighbour_fluid: PackedByteArray, face: int) -> void:
	match face:
		BlockDB.FACE_NX:
			for local_y in ChunkData.SIZE:
				for local_z in ChunkData.SIZE:
					var index := ChunkData.cell_index(ChunkData.SIZE - 1, local_y, local_z)
					var target := padded_index(-1, local_y, local_z)
					_padded[target] = neighbour_blocks[index]
					_padded_fluid[target] = neighbour_fluid[index]
		BlockDB.FACE_PX:
			for local_y in ChunkData.SIZE:
				for local_z in ChunkData.SIZE:
					var index := ChunkData.cell_index(0, local_y, local_z)
					var target := padded_index(ChunkData.SIZE, local_y, local_z)
					_padded[target] = neighbour_blocks[index]
					_padded_fluid[target] = neighbour_fluid[index]
		BlockDB.FACE_NY:
			for local_z in ChunkData.SIZE:
				for local_x in ChunkData.SIZE:
					var index := ChunkData.cell_index(local_x, ChunkData.SIZE - 1, local_z)
					var target := padded_index(local_x, -1, local_z)
					_padded[target] = neighbour_blocks[index]
					_padded_fluid[target] = neighbour_fluid[index]
		BlockDB.FACE_PY:
			for local_z in ChunkData.SIZE:
				for local_x in ChunkData.SIZE:
					var index := ChunkData.cell_index(local_x, 0, local_z)
					var target := padded_index(local_x, ChunkData.SIZE, local_z)
					_padded[target] = neighbour_blocks[index]
					_padded_fluid[target] = neighbour_fluid[index]
		BlockDB.FACE_NZ:
			for local_y in ChunkData.SIZE:
				for local_x in ChunkData.SIZE:
					var index := ChunkData.cell_index(local_x, local_y, ChunkData.SIZE - 1)
					var target := padded_index(local_x, local_y, -1)
					_padded[target] = neighbour_blocks[index]
					_padded_fluid[target] = neighbour_fluid[index]
		BlockDB.FACE_PZ:
			for local_y in ChunkData.SIZE:
				for local_x in ChunkData.SIZE:
					var index := ChunkData.cell_index(local_x, local_y, 0)
					var target := padded_index(local_x, local_y, ChunkData.SIZE)
					_padded[target] = neighbour_blocks[index]
					_padded_fluid[target] = neighbour_fluid[index]


func _emit_faces(chunk: ChunkData, world: VoxelWorld) -> void:
	var blocks := chunk.blocks
	var origin := VoxelWorld.chunk_origin(chunk.coord)
	var base := Vector3(origin)
	var biomes := chunk.biomes
	# Hoist the definition tables and the padded buffer: this loop runs 4096 times
	# per chunk and every static member access or helper call is measurable.
	var padded := _padded
	var opaque := BlockDB.opaque
	var liquid := BlockDB.liquid
	var cull_same := BlockDB.cull_same
	var solid := BlockDB.solid
	var stride := FACE_STRIDE
	for index in ChunkData.CELLS:
		var block_id := int(blocks[index])
		if block_id == BlockDB.AIR:
			continue
		var local_x := index % ChunkData.SIZE
		var local_z := (index / ChunkData.SIZE) % ChunkData.SIZE
		var local_y := index / LAYER_CELLS
		var centre := Vector3(local_x + 0.5, local_y + 0.5, local_z + 0.5)
		var is_deco := solid[block_id] == 0 and liquid[block_id] == 0
		var tint := Color.WHITE
		if block_id == BlockDB.GRASS or block_id == BlockDB.DRY_GRASS or block_id == BlockDB.OAK_LEAVES \
				or block_id == BlockDB.PINE_LEAVES or is_deco:
			tint = WorldGen.BIOME_TINTS[biomes[ChunkData.column_index(local_x, local_z)]]
		if is_deco:
			_emit_deco(block_id, centre, tint)
			continue
		var layer := BlockDB.layer_of(block_id)
		var is_water := block_id == BlockDB.WATER
		if is_water:
			layer = BlockDB.LAYER_WATER
		var surface: Dictionary = _buffers[layer]
		var padded_centre := padded_index(local_x, local_y, local_z)
		var surface_height := 1.0
		if is_water:
			var above := int(padded[padded_centre + stride[BlockDB.FACE_PY]])
			var level := int(chunk.fluid[index])
			surface_height = 1.0 if above == block_id else WATER_RENDER_HEIGHT * clampf(float(level) / 8.0, 0.125, 1.0)
		var is_liquid := liquid[block_id] == 1
		var culls := cull_same[block_id] == 1
		var world_cell := origin + Vector3i(local_x, local_y, local_z)
		for face in 6:
			var neighbour := int(padded[padded_centre + stride[face]])
			# Inlined `BlockDB.hides_neighbour_face`, kept identical to that
			# helper by `test_block_db`.
			if neighbour != BlockDB.AIR:
				if is_liquid:
					if liquid[neighbour] == 1:
						continue
				elif opaque[neighbour] == 1:
					continue
				elif neighbour == block_id and culls:
					continue
			if is_water:
				_emit_water_face(surface, centre, base + centre, face, FACE_NORMAL_I[face], surface_height, block_id, world_cell)
			else:
				_emit_face(surface, centre, face, block_id, tint, 1.0)
				if solid[block_id] == 1:
					_emit_collision(centre, face)


func _emit_face(surface: Dictionary, centre: Vector3, face: int, block_id: int, tint: Color, height_offset: float) -> void:
	var vertices: PackedVector3Array = surface["vertex"]
	var normals: PackedVector3Array = surface["normal"]
	var uvs: PackedVector2Array = surface["uv"]
	var uv2s: PackedVector2Array = surface["uv2"]
	var colors: PackedColorArray = surface["color"]
	var indices: PackedInt32Array = surface["index"]
	var corners: Array = FACE_CORNERS[face]
	var face_uvs: Array = FACE_UVS[face]
	var normal: Vector3 = FACE_NORMALS[face]
	var layer := face_layer[block_id * 6 + face]
	var shade: float = FACE_SHADE[face]
	var tone := Color(tint.r * shade, tint.g * shade, tint.b * shade, 1.0)
	var uv2 := Vector2(float(layer), 0.0)
	var top := 1.0 if face != BlockDB.FACE_NY else 0.0
	var base_index := vertices.size()
	for corner_index in 4:
		var corner: Vector3 = corners[corner_index]
		if top > 0.0 and corner.y > 0.0:
			corner.y -= 1.0 - height_offset
		vertices.append(centre + corner)
		normals.append(normal)
		uvs.append(face_uvs[corner_index])
		uv2s.append(uv2)
		colors.append(tone)
	for quad_index in QUAD_INDICES:
		indices.append(base_index + quad_index)
	surface["faces"] = int(surface["faces"]) + 1


## Water faces are emitted in chunk-local space like every other layer (the chunk
## node carries the world offset), but their UVs are derived from the *world*
## position so the animated surface tiles seamlessly across chunk borders.
## The top edge follows the fluid surface height.
func _emit_water_face(surface: Dictionary, local_centre: Vector3, world_centre: Vector3, face: int, normal: Vector3i, surface_height: float, block_id: int, world_position: Vector3i) -> void:
	var vertices: PackedVector3Array = surface["vertex"]
	var normals: PackedVector3Array = surface["normal"]
	var uvs: PackedVector2Array = surface["uv"]
	var uv2s: PackedVector2Array = surface["uv2"]
	var colors: PackedColorArray = surface["color"]
	var indices: PackedInt32Array = surface["index"]
	var corners: Array = FACE_CORNERS[face]
	var face_normal := Vector3(normal)
	var layer := face_layer[block_id * 6 + face]
	var base_index := vertices.size()
	for corner_index in 4:
		var corner: Vector3 = corners[corner_index]
		if corner.y > 0.0 and face != BlockDB.FACE_NY:
			corner.y -= 1.0 - surface_height
		vertices.append(local_centre + corner)
		normals.append(face_normal)
		var world_corner := world_centre + corner
		if face_normal.y != 0.0:
			uvs.append(Vector2(world_corner.x * 0.25, world_corner.z * 0.25))
		else:
			var horizontal := world_corner.z if face_normal.x != 0.0 else world_corner.x
			uvs.append(Vector2(horizontal * 0.25, world_corner.y * 0.25))
		uv2s.append(Vector2(float(layer), 0.0))
		# Shade water slightly darker with depth (lower surface = deeper).
		var depth_tone := 0.72 + 0.28 * surface_height
		colors.append(Color(depth_tone, depth_tone, depth_tone, 1.0))
	for quad_index in QUAD_INDICES:
		indices.append(base_index + quad_index)
	surface["faces"] = int(surface["faces"]) + 1


func _emit_collision(centre: Vector3, face: int) -> void:
	var vertices: PackedVector3Array = _collision["vertex"]
	var indices: PackedInt32Array = _collision["index"]
	var corners: Array = FACE_CORNERS[face]
	var base_index := vertices.size()
	for corner_index in 4:
		vertices.append(centre + corners[corner_index])
	for quad_index in QUAD_INDICES:
		indices.append(base_index + quad_index)


## Crossed quads for flowers, grass tufts and other non-cube decoration.
func _emit_deco(block_id: int, centre: Vector3, tint: Color) -> void:
	var surface: Dictionary = _buffers[BlockDB.LAYER_DECO]
	var vertices: PackedVector3Array = surface["vertex"]
	var normals: PackedVector3Array = surface["normal"]
	var uvs: PackedVector2Array = surface["uv"]
	var uv2s: PackedVector2Array = surface["uv2"]
	var colors: PackedColorArray = surface["color"]
	var indices: PackedInt32Array = surface["index"]
	var layer := face_layer[block_id * 6 + BlockDB.FACE_PY]
	var uv2 := Vector2(float(layer), 0.0)
	var tone := Color(tint.r, tint.g, tint.b, 1.0)
	var half := 0.5 - 0.06
	var bottom := centre + Vector3(0.0, -0.5, 0.0)
	var top := centre + Vector3(0.0, 0.5, 0.0)
	var plane_a := [
		bottom + Vector3(-half, 0.0, -half), top + Vector3(-half, 0.0, -half),
		top + Vector3(half, 0.0, half), bottom + Vector3(half, 0.0, half),
	]
	var plane_b := [
		bottom + Vector3(half, 0.0, -half), top + Vector3(half, 0.0, -half),
		top + Vector3(-half, 0.0, half), bottom + Vector3(-half, 0.0, half),
	]
	var quad_uvs: Array = [Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)]
	for plane: Array in [plane_a, plane_b]:
		var base_index := vertices.size()
		for corner_index in 4:
			vertices.append(plane[corner_index])
			normals.append(Vector3.UP)
			uvs.append(quad_uvs[corner_index])
			uv2s.append(uv2)
			colors.append(tone)
		for quad_index in QUAD_INDICES:
			indices.append(base_index + quad_index)
		surface["faces"] = int(surface["faces"]) + 1


func _build_array_mesh(layers: Array) -> ArrayMesh:
	var mesh: ArrayMesh = null
	for layer: int in layers:
		var surface: Dictionary = _buffers[layer]
		var indices: PackedInt32Array = surface["index"]
		if indices.is_empty():
			continue
		if mesh == null:
			mesh = ArrayMesh.new()
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = surface["vertex"]
		arrays[Mesh.ARRAY_NORMAL] = surface["normal"]
		arrays[Mesh.ARRAY_TEX_UV] = surface["uv"]
		arrays[Mesh.ARRAY_TEX_UV2] = surface["uv2"]
		arrays[Mesh.ARRAY_COLOR] = surface["color"]
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, materials.for_layer(layer))
	return mesh
